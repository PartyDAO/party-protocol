// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { Party } from "../party/Party.sol";
import { PartyGovernanceNFT } from "../party/PartyGovernanceNFT.sol";
import { PartyFactory } from "../party/PartyFactory.sol";
import { IERC721 } from "../tokens/IERC721.sol";
import { MetadataProvider } from "../renderers/MetadataProvider.sol";

contract BondingCurveAuthority {
    error InvalidMessageValue();
    error Unauthorized();
    error InvalidCreatorFee();
    error PartyNotSupported();

    mapping(Party => PartyInfo) public partyInfos;
    uint16 private partyDaoFeeBps;
    uint16 private treasuryFeeBps;
    uint256 private constant PARTY_CARD_VOTING_POWER = 0.1 ether;
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

        buyPartyCards(party, 1);
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

        buyPartyCards(party, 1);
    }

    function buyPartyCards(Party party, uint80 amount) public payable {
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

        for (uint256 i = 0; i < amount; i++) {
            party.mint(msg.sender, PARTY_CARD_VOTING_POWER, address(0));
        }
    }

    function sellPartyCards(Party party, uint256[] memory tokenIds) external {
        PartyInfo memory partyInfo = partyInfos[party];

        if (partyInfo.creator == address(0)) {
            revert PartyNotSupported();
        }

        uint256 amount = tokenIds.length;
        uint256 bondingCurvePrice = _getBondingCurvePrice(partyInfo.supply, amount);
        uint256 partyDaoFee = (bondingCurvePrice * partyDaoFeeBps) / BPS;
        uint256 treasuryFee = (bondingCurvePrice * treasuryFeeBps) / BPS;
        uint256 creatorFee = (bondingCurvePrice * partyInfo.creatorFee) / BPS;

        partyInfos[party].supply = uint80(partyInfo.supply - amount);

        for (uint256 i = 0; i < amount; i++) {
            if (party.ownerOf(tokenIds[i]) != msg.sender) {
                revert Unauthorized();
            }
            party.burn(tokenIds[i]);
        }

        if (creatorFee != 0) partyInfo.creator.transfer(partyDaoFee);
        payable(address(party)).transfer(treasuryFee);
        payable(msg.sender).transfer(bondingCurvePrice - partyDaoFee - treasuryFee - creatorFee);
    }

    function getPriceToSell(Party party, uint256 amount) external view returns (uint256) {
        PartyInfo memory partyInfo = partyInfos[party];
        uint256 bondingCurvePrice = _getBondingCurvePrice(partyInfo.supply, amount);
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
        uint256 previousSupply,
        uint256 amount
    ) private pure returns (uint256) {
        uint256 totalPrice = 0.001 ether * amount;

        for (uint i = 0; i < amount; i++) {
            totalPrice += ((previousSupply + i) * (previousSupply + i) * 1 ether) / 50_000;
        }
        return totalPrice;
    }

    function setTreasuryFee(uint16 newTreasuryFeeBps) external {
        if (msg.sender != PARTY_DAO) {
            revert Unauthorized();
        }
        treasuryFeeBps = newTreasuryFeeBps;
    }

    function setPartyDaoFee(uint16 newPartyDaoFeeBps) external {
        if (msg.sender != PARTY_DAO) {
            revert Unauthorized();
        }
        partyDaoFeeBps = newPartyDaoFeeBps;
    }

    function setCreatorFee(Party party, uint16 newCreatorFee) external {
        if (msg.sender != partyInfos[party].creator) {
            revert Unauthorized();
        }
        partyInfos[party].creatorFee = newCreatorFee;
    }

    function claimPartyDaoFee() external {
        if (msg.sender != PARTY_DAO) {
            revert Unauthorized();
        }
        PARTY_DAO.transfer(address(this).balance);
    }
}
