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
    error InvalidTreasuryFee();
    error InvalidPartyDaoFee();
    error PartyNotSupported();
    error InvalidTotalVotingPower();

    event TreasuryFeeUpdated(uint16 previousTreasuryFee, uint16 newTreasuryFee);
    event PartyDaoFeeUpdated(uint16 previousPartyDaoFee, uint16 newPartyDaoFee);
    event CreatorFeeUpdated(uint16 previousCreatorFee, uint16 newCreatorFee);
    event PartyDaoFeesClaimed(uint96 amount);
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

    /// @notice Info for each party controlled by this authority
    mapping(Party => PartyInfo) public partyInfos;
    /// @notice The global party dao fee basis points
    uint16 public partyDaoFeeBps;
    /// @notice The global treasury fee basis points
    uint16 public treasuryFeeBps;
    /// @notice The global creator fee basis points
    uint16 public creatorFeeBps;
    /// @notice The amount of party dao fees claimable
    uint96 public partyDaoFeeClaimable;

    /// @notice The intrinsic voting power of party cards minted by this contract
    uint96 private constant PARTY_CARD_VOTING_POWER = uint96(0.1 ether);
    address payable private immutable PARTY_DAO;
    uint16 private constant BPS = 10_000;
    uint16 private constant MAX_CREATOR_FEE = 250;
    uint16 private constant MAX_TREASURY_FEE = 1000;
    uint16 private constant MAX_PARTY_DAO_FEE = 250;

    struct BondingCurvePartyOptions {
        PartyFactory partyFactory;
        Party partyImpl;
        Party.PartyOptions opts;
        // boolean specifying if creator fees are collected
        bool creatorFeeOn;
    }

    struct PartyInfo {
        address payable creator;
        uint80 supply;
        bool creatorFeeOn;
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
        uint16 initialTreasuryFeeBps,
        uint16 initialCreatorFeeBps
    ) {
        if (initialPartyDaoFeeBps > MAX_PARTY_DAO_FEE) {
            revert InvalidPartyDaoFee();
        }
        if (initialTreasuryFeeBps > MAX_TREASURY_FEE) {
            revert InvalidTreasuryFee();
        }
        if (initialCreatorFeeBps > MAX_CREATOR_FEE) {
            revert InvalidCreatorFee();
        }
        partyDaoFeeBps = initialPartyDaoFeeBps;
        treasuryFeeBps = initialTreasuryFeeBps;
        creatorFeeBps = initialCreatorFeeBps;
        PARTY_DAO = partyDao;
    }

    /**
     * @notice Create a new party that will have a dynamic price
     * @param partyOpts options specified for creating the party
     * @return party The address of the newly created party
     */
    function createParty(
        BondingCurvePartyOptions memory partyOpts
    ) external payable returns (Party party) {
        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        if (partyOpts.opts.governance.totalVotingPower != 0) {
            revert InvalidTotalVotingPower();
        }

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
            creatorFeeOn: partyOpts.creatorFeeOn
        });

        buyPartyCards(party, 1, address(0));
    }

    /**
     * @notice Create a new party with metadata that will have a dynamic price
     * @param partyOpts options specified for creating the party
     * @param customMetadataProvider the metadata provider to use for the party
     * @param customMetadata the metadata to use for the party
     * @return party The address of the newly created party
     */
    function createPartyWithMetadata(
        BondingCurvePartyOptions memory partyOpts,
        MetadataProvider customMetadataProvider,
        bytes memory customMetadata
    ) external payable returns (Party party) {
        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        if (partyOpts.opts.governance.totalVotingPower != 0) {
            revert InvalidTotalVotingPower();
        }

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
            creatorFeeOn: partyOpts.creatorFeeOn
        });

        buyPartyCards(party, 1, address(0));
    }

    /**
     * @notice Buy party cards from the bonding curve
     * @param party The party to buy cards for
     * @param amount The amount of cards to buy
     * @param initialDelegate The initial delegate for governance
     */
    function buyPartyCards(Party party, uint80 amount, address initialDelegate) public payable {
        PartyInfo memory partyInfo = partyInfos[party];

        if (partyInfo.creator == address(0)) {
            revert PartyNotSupported();
        }

        uint256 bondingCurvePrice = _getBondingCurvePrice(partyInfo.supply, amount);
        uint256 partyDaoFee = (bondingCurvePrice * partyDaoFeeBps) / BPS;
        uint256 treasuryFee = (bondingCurvePrice * treasuryFeeBps) / BPS;
        uint256 creatorFee = (bondingCurvePrice * (partyInfo.creatorFeeOn ? creatorFeeBps : 0)) /
            BPS;

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

    /**
     * @notice Sell party cards to the bonding curve
     * @param party The party to sell cards for
     * @param tokenIds The token ids to sell
     */
    function sellPartyCards(Party party, uint256[] memory tokenIds) external {
        PartyInfo memory partyInfo = partyInfos[party];

        if (partyInfo.creator == address(0)) {
            revert PartyNotSupported();
        }

        uint80 amount = uint80(tokenIds.length);
        uint256 bondingCurvePrice = _getBondingCurvePrice(partyInfo.supply - amount, amount);
        uint256 partyDaoFee = (bondingCurvePrice * partyDaoFeeBps) / BPS;
        uint256 treasuryFee = (bondingCurvePrice * treasuryFeeBps) / BPS;
        uint256 creatorFee = (bondingCurvePrice * (partyInfo.creatorFeeOn ? creatorFeeBps : 0)) /
            BPS;

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

    /**
     * @notice Get the sale proceeds for a given amount of cards
     * @param party The party to get the sale proceeds for
     * @param amount The amount of cards that would be sold
     * @return The sale proceeds for the given amount of cards that would be sent to the seller
     */
    function getSaleProceeds(Party party, uint256 amount) external view returns (uint256) {
        PartyInfo memory partyInfo = partyInfos[party];
        uint256 bondingCurvePrice = _getBondingCurvePrice(partyInfo.supply - amount, amount);
        return
            (bondingCurvePrice *
                (BPS -
                    partyDaoFeeBps -
                    treasuryFeeBps -
                    (partyInfo.creatorFeeOn ? creatorFeeBps : 0))) / BPS;
    }

    /**
     * @notice Get the price to buy a given amount of cards
     * @param party The party to get the price for
     * @param amount The amount of cards that would be bought
     * @return The price to buy the given amount of cards
     */
    function getPriceToBuy(Party party, uint256 amount) external view returns (uint256) {
        PartyInfo memory partyInfo = partyInfos[party];
        uint256 bondingCurvePrice = _getBondingCurvePrice(partyInfo.supply, amount);
        return
            (bondingCurvePrice *
                (BPS +
                    partyDaoFeeBps +
                    treasuryFeeBps +
                    (partyInfo.creatorFeeOn ? creatorFeeBps : 0))) / BPS;
    }

    /**
     * @notice Returns the bonding curve price for a given amount of cards
     *         for a given lower supply.
     * @param lowerSupply The lower supply of either the start supply or end supply
     *        For example: if burning, this would be the supply after burning.
     * @param amount The number of cards to calculate the price for
     * @return The bonding curve price for these cards
     */
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

    /**
     * @notice Set the treasury fee. Only callable by party dao.
     * @param newTreasuryFeeBps The new treasury fee
     */
    function setTreasuryFee(uint16 newTreasuryFeeBps) external onlyPartyDao {
        if (newTreasuryFeeBps > MAX_TREASURY_FEE) {
            revert InvalidTreasuryFee();
        }
        emit TreasuryFeeUpdated(treasuryFeeBps, newTreasuryFeeBps);
        treasuryFeeBps = newTreasuryFeeBps;
    }

    /**
     * @notice Set the party dao fee. Only callable by party dao.
     * @param newPartyDaoFeeBps The new party dao fee
     */
    function setPartyDaoFee(uint16 newPartyDaoFeeBps) external onlyPartyDao {
        if (newPartyDaoFeeBps > MAX_PARTY_DAO_FEE) {
            revert InvalidPartyDaoFee();
        }
        emit PartyDaoFeeUpdated(partyDaoFeeBps, newPartyDaoFeeBps);
        partyDaoFeeBps = newPartyDaoFeeBps;
    }

    /**
     * @notice Set the creator fee for all parties. Can only be called by party dao.
     * @param newCreatorFeeBps The new creator fee
     */
    function setCreatorFee(uint16 newCreatorFeeBps) external onlyPartyDao {
        if (newCreatorFeeBps > MAX_CREATOR_FEE) {
            revert InvalidCreatorFee();
        }
        emit CreatorFeeUpdated(creatorFeeBps, newCreatorFeeBps);
        creatorFeeBps = newCreatorFeeBps;
    }

    /**
     * @notice Claim the party dao fees. Only callable by party dao.
     */
    function claimPartyDaoFees() external onlyPartyDao {
        uint96 _partyDaoFeeClaimable = partyDaoFeeClaimable;
        partyDaoFeeClaimable = 0;
        PARTY_DAO.transfer(_partyDaoFeeClaimable);
        emit PartyDaoFeesClaimed(_partyDaoFeeClaimable);
    }
}
