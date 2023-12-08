// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { Party } from "../party/Party.sol";
import { PartyGovernanceNFT } from "../party/PartyGovernanceNFT.sol";
import { PartyFactory } from "../party/PartyFactory.sol";
import { IERC721 } from "../tokens/IERC721.sol";
import { MetadataProvider } from "../renderers/MetadataProvider.sol";
import { LibSafeCast } from "contracts/utils/LibSafeCast.sol";

contract BondingCurveAuthority {
    using LibSafeCast for uint256;

    error InvalidMessageValue();
    error Unauthorized();
    error InvalidCreatorFee();
    error PartyNotSupported();

    event TreasuryFeeUpdated(uint16 previousTreasuryFee, uint16 newTreasuryFee);
    event PartyDaoFeeUpdated(uint16 previousPartyDaoFee, uint16 newPartyDaoFee);
    event PartyCardsBought(
        Party indexed party,
        address indexed buyer,
        uint256[] tokenIds,
        uint256 totalPrice,
        uint256 partyDaoFee,
        uint256 treasuryFee,
        uint256 creatorFee
    );
    event PartyCardsSold(
        Party indexed party,
        address indexed seller,
        uint256[] tokenIds,
        uint256 sellerProceeds,
        uint256 partyDaoFee,
        uint256 treasuryFee,
        uint256 creatorFee
    );

    mapping(Party => PartyInfo) public partyInfos;
    uint16 public partyDaoFeeBps;
    uint16 public treasuryFeeBps;
    uint96 private partyDaoFeeClaimable;

    uint96 private constant PARTY_CARD_VOTING_POWER = uint80(0.1 ether);
    address payable private immutable PARTY_DAO;
    uint16 private constant BPS = 10_000;

    struct BondingCurvePartyOptions {
        PartyFactory partyFactory;
        Party partyImpl;
        Party.PartyOptions opts;
        uint16 creatorFee;
    }

    struct PartyInfo {
        address payable creator;
        uint80 supply;
        uint16 creatorFee;
    }

    modifier onlyPartyDao() {
        if (msg.sender != PARTY_DAO) {
            revert Unauthorized();
        }
        _;
    }

    constructor(
        address payable partyDao,
        uint16 initialPartyDaoFeeBps,
        uint16 initialTreasuryFeeBps
    ) {
        partyDaoFeeBps = initialPartyDaoFeeBps;
        treasuryFeeBps = initialTreasuryFeeBps;
        PARTY_DAO = partyDao;
    }

    function createParty(
        BondingCurvePartyOptions memory partyOpts
    ) external payable returns (Party party) {
        if (partyOpts.creatorFee > 500) {
            revert InvalidCreatorFee();
        }

        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        party = partyOpts.partyFactory.createParty(
            partyOpts.partyImpl,
            authorities,
            partyOpts.opts,
            new IERC721[](0),
            new uint256[](0),
            0
        );

        partyInfos[party] = PartyInfo({
            creator: payable(msg.sender),
            supply: 0,
            creatorFee: partyOpts.creatorFee
        });

        buyPartyCards(party, 1, address(0));
    }

    function createPartyWithMetadata(
        BondingCurvePartyOptions memory partyOpts,
        MetadataProvider customMetadataProvider,
        bytes memory customMetadata
    ) external payable returns (Party party) {
        if (partyOpts.creatorFee > 500) {
            revert InvalidCreatorFee();
        }

        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        party = partyOpts.partyFactory.createPartyWithMetadata(
            partyOpts.partyImpl,
            authorities,
            partyOpts.opts,
            new IERC721[](0),
            new uint256[](0),
            0,
            customMetadataProvider,
            customMetadata
        );

        partyInfos[party] = PartyInfo({
            creator: payable(msg.sender),
            supply: 0,
            creatorFee: partyOpts.creatorFee
        });

        buyPartyCards(party, 1, address(0));
    }

    function buyPartyCards(Party party, uint80 amount, address initialDelegate) public payable {
        PartyInfo memory partyInfo = partyInfos[party];

        if (partyInfo.creator == address(0)) {
            revert PartyNotSupported();
        }

        uint256 bondingCurvePrice = _getBondingCurvePrice(partyInfo.supply, amount);
        uint256 partyDaoFee = (bondingCurvePrice * partyDaoFeeBps) / BPS;
        uint256 treasuryFee = (bondingCurvePrice * treasuryFeeBps) / BPS;
        uint256 creatorFee = (bondingCurvePrice * partyInfo.creatorFee) / BPS;

        if (
            amount == 0 || msg.value != bondingCurvePrice + partyDaoFee + treasuryFee + creatorFee
        ) {
            revert InvalidMessageValue();
        }

        partyInfos[party].supply = partyInfo.supply + amount;

        payable(address(party)).transfer(treasuryFee);
        if (creatorFee != 0) partyInfo.creator.transfer(creatorFee);
        partyDaoFeeClaimable += partyDaoFee.safeCastUint256ToUint96();

        party.increaseTotalVotingPower(PARTY_CARD_VOTING_POWER * amount);
        uint256[] memory tokenIds = new uint256[](amount);
        for (uint256 i = 0; i < amount; i++) {
            tokenIds[i] = party.mint(msg.sender, PARTY_CARD_VOTING_POWER, initialDelegate);
        }

        emit PartyCardsBought(
            party,
            msg.sender,
            tokenIds,
            msg.value,
            partyDaoFee,
            treasuryFee,
            creatorFee
        );
    }

    function sellPartyCards(Party party, uint256[] memory tokenIds) external {
        PartyInfo memory partyInfo = partyInfos[party];

        if (partyInfo.creator == address(0)) {
            revert PartyNotSupported();
        }

        uint80 amount = uint80(tokenIds.length);
        uint256 bondingCurvePrice = _getBondingCurvePrice(partyInfo.supply - amount, amount);
        uint256 partyDaoFee = (bondingCurvePrice * partyDaoFeeBps) / BPS;
        uint256 treasuryFee = (bondingCurvePrice * treasuryFeeBps) / BPS;
        uint256 creatorFee = (bondingCurvePrice * partyInfo.creatorFee) / BPS;

        partyInfos[party].supply = partyInfo.supply - amount;

        for (uint256 i = 0; i < amount; i++) {
            address tokenOwner = party.ownerOf(tokenIds[i]);
            if (
                tokenOwner != msg.sender &&
                party.isApprovedForAll(tokenOwner, msg.sender) != true &&
                party.getApproved(tokenIds[i]) != msg.sender
            ) {
                revert Unauthorized();
            }
            party.burn(tokenIds[i]);
        }
        party.decreaseTotalVotingPower(PARTY_CARD_VOTING_POWER * amount);

        uint256 sellerProceeds = bondingCurvePrice - partyDaoFee - treasuryFee - creatorFee;
        if (creatorFee != 0) partyInfo.creator.transfer(partyDaoFee);
        payable(address(party)).transfer(treasuryFee);
        payable(msg.sender).transfer(sellerProceeds);
        partyDaoFeeClaimable += partyDaoFee.safeCastUint256ToUint96();

        emit PartyCardsSold(
            party,
            msg.sender,
            tokenIds,
            sellerProceeds,
            partyDaoFee,
            treasuryFee,
            creatorFee
        );
    }

    function getSaleProceeds(Party party, uint256 amount) external view returns (uint256) {
        PartyInfo memory partyInfo = partyInfos[party];
        uint256 bondingCurvePrice = _getBondingCurvePrice(partyInfo.supply - amount, amount);
        return
            (bondingCurvePrice * (BPS - partyDaoFeeBps - treasuryFeeBps - partyInfo.creatorFee)) /
            BPS;
    }

    function getPriceToBuy(Party party, uint256 amount) external view returns (uint256) {
        PartyInfo memory partyInfo = partyInfos[party];
        uint256 bondingCurvePrice = _getBondingCurvePrice(partyInfo.supply, amount);
        return
            (bondingCurvePrice * (BPS + partyDaoFeeBps + treasuryFeeBps + partyInfo.creatorFee)) /
            BPS;
    }

    function _getBondingCurvePrice(
        uint256 lowerSupply,
        uint256 amount
    ) internal pure returns (uint256) {
        // Using the function 1 ether * x ** 2 / 50_000 + 0.001 eth
        uint256 amountSquared = amount * amount;
        return
            (1 ether *
                (amount *
                    lowerSupply *
                    lowerSupply +
                    (amountSquared - amount) *
                    lowerSupply +
                    (2 * amountSquared * amount + amount - 3 * amountSquared) /
                    6)) /
            50_000 +
            amount *
            0.001 ether;
    }

    function setTreasuryFee(uint16 newTreasuryFeeBps) external onlyPartyDao {
        emit TreasuryFeeUpdated(treasuryFeeBps, newTreasuryFeeBps);
        treasuryFeeBps = newTreasuryFeeBps;
    }

    function setPartyDaoFee(uint16 newPartyDaoFeeBps) external onlyPartyDao {
        emit PartyDaoFeeUpdated(partyDaoFeeBps, newPartyDaoFeeBps);
        partyDaoFeeBps = newPartyDaoFeeBps;
    }

    function setCreatorFee(Party party, uint16 newCreatorFee) external {
        if (msg.sender != partyInfos[party].creator) {
            revert Unauthorized();
        }
        partyInfos[party].creatorFee = newCreatorFee;
    }

    function claimPartyDaoFees() external onlyPartyDao {
        partyDaoFeeClaimable = 0;
        PARTY_DAO.transfer(partyDaoFeeClaimable);
    }
}
