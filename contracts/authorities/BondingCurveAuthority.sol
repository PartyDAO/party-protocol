// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { Party } from "../party/Party.sol";
import { PartyFactory } from "../party/PartyFactory.sol";
import { IERC721 } from "../tokens/IERC721.sol";
import { MetadataProvider } from "../renderers/MetadataProvider.sol";
import { LibSafeCast } from "contracts/utils/LibSafeCast.sol";
import { ProposalStorage } from "contracts/proposals/ProposalStorage.sol";

contract BondingCurveAuthority {
    using LibSafeCast for uint256;

    error InvalidMessageValue();
    error Unauthorized();
    error InvalidCreatorFee();
    error InvalidTreasuryFee();
    error InvalidPartyDaoFee();
    error PartyNotSupported();
    error ExistingParty();
    error InvalidTotalVotingPower();
    error ExecutionDelayTooShort();
    error EthTransferFailed();
    error ExcessSlippage();
    error AddAuthorityProposalNotSupported();
    error SellZeroPartyCards();
    error DistributionsNotSupported();

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
    uint16 private constant MAX_CREATOR_FEE = 250; // 2.5%
    uint16 private constant MAX_TREASURY_FEE = 1000; // 10%
    uint16 private constant MAX_PARTY_DAO_FEE = 250; // 2.5%
    /// @notice The minimum execution delay for party governance
    uint40 private constant MIN_EXECUTION_DELAY = 1 seconds;

    /// @notice Struct containing options for creating a party
    struct BondingCurvePartyOptions {
        // The party factory address to use
        PartyFactory partyFactory;
        // The party implementation address to use
        Party partyImpl;
        // Options for the party. See `Party.sol` for more info
        Party.PartyOptions opts;
        // boolean specifying if creator fees are collected
        bool creatorFeeOn;
        // The value of a in the bonding curve formula 1 ether * x ** 2 / a + b
        // used by the Party to price cards
        uint32 a;
        // The value of b in the bonding curve formula 1 ether * x ** 2 / a + b
        // used by the Party to price cards
        uint80 b;
    }

    /// @notice Struct containing info stored for a party
    struct PartyInfo {
        // The original creator of the party
        address payable creator;
        // The supply of party cards tracked by this contract
        uint80 supply;
        // boolean specifying if creator fees are collected
        bool creatorFeeOn;
        // The value of a in the bonding curve formula 1 ether * x ** 2 / a + b
        // used by the Party to price cards
        uint32 a;
        // The value of b in the bonding curve formula 1 ether * x ** 2 / a + b
        // used by the Party to price cards
        uint80 b;
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
     * @param amountToBuy The amount of party cards the creator buys initially
     * @return party The address of the newly created party
     */
    function createParty(
        BondingCurvePartyOptions memory partyOpts,
        uint80 amountToBuy
    ) external payable returns (Party party) {
        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        _validateGovernanceOpts(partyOpts.opts);

        party = partyOpts.partyFactory.createParty(
            partyOpts.partyImpl,
            authorities,
            partyOpts.opts,
            new IERC721[](0),
            new uint256[](0),
            0
        );

        if (partyInfos[party].creator != address(0)) {
            revert ExistingParty();
        }

        partyInfos[party] = PartyInfo({
            creator: payable(msg.sender),
            supply: 0,
            creatorFeeOn: partyOpts.creatorFeeOn,
            a: partyOpts.a,
            b: partyOpts.b
        });

        buyPartyCards(party, amountToBuy, address(0));
    }

    /**
     * @notice Create a new party with metadata that will have a dynamic price
     * @param partyOpts options specified for creating the party
     * @param customMetadataProvider the metadata provider to use for the party
     * @param customMetadata the metadata to use for the party
     * @param amountToBuy The amount of party cards the creator buys initially
     * @return party The address of the newly created party
     */
    function createPartyWithMetadata(
        BondingCurvePartyOptions memory partyOpts,
        MetadataProvider customMetadataProvider,
        bytes memory customMetadata,
        uint80 amountToBuy
    ) external payable returns (Party party) {
        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        _validateGovernanceOpts(partyOpts.opts);

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

        if (partyInfos[party].creator != address(0)) {
            revert ExistingParty();
        }

        partyInfos[party] = PartyInfo({
            creator: payable(msg.sender),
            supply: 0,
            creatorFeeOn: partyOpts.creatorFeeOn,
            a: partyOpts.a,
            b: partyOpts.b
        });

        buyPartyCards(party, amountToBuy, address(0));
    }

    function _validateGovernanceOpts(Party.PartyOptions memory partyOpts) internal pure {
        if (partyOpts.governance.totalVotingPower != 0) {
            revert InvalidTotalVotingPower();
        }
        // Note: while the `executionDelay` is not enforced to be over 1 second,
        //       it is strongly recommended for it to be a long period
        //       (greater than 1 day). This prevents an attacker from buying cards,
        //       draining the party and then selling before a host can react.
        if (partyOpts.governance.executionDelay < MIN_EXECUTION_DELAY) {
            revert ExecutionDelayTooShort();
        }

        if (partyOpts.proposalEngine.enableAddAuthorityProposal) {
            revert AddAuthorityProposalNotSupported();
        }

        if (
            partyOpts.proposalEngine.distributionsConfig !=
            ProposalStorage.DistributionsConfig.NotAllowed
        ) {
            revert DistributionsNotSupported();
        }
    }

    /**
     * @notice Buy party cards from the bonding curve
     * @param party The party to buy cards for
     * @param amount The amount of cards to buy
     * @param initialDelegate The initial delegate for governance
     * @return tokenIds The token ids of the party cards that were bought
     */
    function buyPartyCards(
        Party party,
        uint80 amount,
        address initialDelegate
    ) public payable returns (uint256[] memory tokenIds) {
        PartyInfo memory partyInfo = partyInfos[party];

        if (partyInfo.creator == address(0)) {
            revert PartyNotSupported();
        }

        uint256 bondingCurvePrice = _getBondingCurvePrice(
            partyInfo.supply,
            amount,
            partyInfo.a,
            partyInfo.b
        );
        uint256 partyDaoFee = (bondingCurvePrice * partyDaoFeeBps) / BPS;
        uint256 treasuryFee = (bondingCurvePrice * treasuryFeeBps) / BPS;
        uint256 creatorFee = (bondingCurvePrice * (partyInfo.creatorFeeOn ? creatorFeeBps : 0)) /
            BPS;
        uint256 totalCost = bondingCurvePrice + partyDaoFee + treasuryFee + creatorFee;

        partyInfos[party].supply = partyInfo.supply + amount;

        (bool success, ) = address(party).call{ value: treasuryFee }("");
        if (!success) {
            revert EthTransferFailed();
        }

        if (creatorFee != 0) {
            // Creator fee payment can fail
            (bool creatorFeeSucceeded, ) = partyInfo.creator.call{ value: creatorFee }("");
            if (!creatorFeeSucceeded) {
                totalCost -= creatorFee;
            }
        }

        if (amount == 0 || msg.value < totalCost) {
            revert InvalidMessageValue();
        }

        partyDaoFeeClaimable += partyDaoFee.safeCastUint256ToUint96();
        party.increaseTotalVotingPower(PARTY_CARD_VOTING_POWER * amount);
        tokenIds = new uint256[](amount);
        for (uint256 i = 0; i < amount; i++) {
            tokenIds[i] = party.mint(msg.sender, PARTY_CARD_VOTING_POWER, initialDelegate);
        }

        emit PartyCardsBought(
            party,
            msg.sender,
            tokenIds,
            totalCost,
            partyDaoFee,
            treasuryFee,
            creatorFee
        );

        // Refund excess ETH
        if (msg.value > totalCost) {
            (success, ) = msg.sender.call{ value: msg.value - totalCost }("");
            if (!success) {
                revert EthTransferFailed();
            }
        }
    }

    /**
     * @notice Sell party cards to the bonding curve
     * @param party The party to sell cards for
     * @param tokenIds The token ids to sell
     */
    function sellPartyCards(Party party, uint256[] memory tokenIds, uint256 minProceeds) external {
        if (tokenIds.length == 0) {
            revert SellZeroPartyCards();
        }

        PartyInfo memory partyInfo = partyInfos[party];

        if (partyInfo.creator == address(0)) {
            revert PartyNotSupported();
        }

        uint80 amount = uint80(tokenIds.length);
        uint256 bondingCurvePrice = _getBondingCurvePrice(
            partyInfo.supply - amount,
            amount,
            partyInfo.a,
            partyInfo.b
        );
        uint256 partyDaoFee = (bondingCurvePrice * partyDaoFeeBps) / BPS;
        uint256 treasuryFee = (bondingCurvePrice * treasuryFeeBps) / BPS;
        uint256 creatorFee = (bondingCurvePrice * (partyInfo.creatorFeeOn ? creatorFeeBps : 0)) /
            BPS;

        // Note: 1 is subtracted for each NFT to account for rounding errors
        uint256 sellerProceeds = bondingCurvePrice -
            partyDaoFee -
            treasuryFee -
            creatorFee -
            amount;
        if (sellerProceeds < minProceeds) {
            revert ExcessSlippage();
        }

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

        (bool success, ) = address(party).call{ value: treasuryFee }("");
        if (!success) {
            revert EthTransferFailed();
        }

        if (creatorFee != 0) {
            // Creator fee payment can fail
            (bool creatorFeeSucceeded, ) = partyInfo.creator.call{ value: creatorFee }("");
            if (!creatorFeeSucceeded) {
                sellerProceeds += creatorFee;
            }
        }

        (success, ) = msg.sender.call{ value: sellerProceeds }("");
        if (!success) {
            revert EthTransferFailed();
        }
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
        uint256 bondingCurvePrice = _getBondingCurvePrice(
            partyInfo.supply - amount,
            amount,
            partyInfo.a,
            partyInfo.b
        );
        uint256 partyDaoFee = (bondingCurvePrice * partyDaoFeeBps) / BPS;
        uint256 treasuryFee = (bondingCurvePrice * treasuryFeeBps) / BPS;
        uint256 creatorFee = (bondingCurvePrice * (partyInfo.creatorFeeOn ? creatorFeeBps : 0)) /
            BPS;
        // Note: 1 is subtracted for each NFT to account for rounding errors
        return bondingCurvePrice - partyDaoFee - treasuryFee - creatorFee - amount;
    }

    /**
     * @notice Get the price to buy a given amount of cards
     * @param party The party to get the price for
     * @param amount The amount of cards that would be bought
     * @return The price to buy the given amount of cards
     */
    function getPriceToBuy(Party party, uint80 amount) external view returns (uint256) {
        PartyInfo memory partyInfo = partyInfos[party];
        return
            getPriceToBuy(
                partyInfo.supply,
                amount,
                partyInfo.a,
                partyInfo.b,
                partyInfo.creatorFeeOn
            );
    }

    /**
     * @notice Get the price to buy a given amount of cards
     * @param supply The current supply of the party
     * @param amount The amount of cards that would be bought
     * @param a The value of a in the bonding curve formula 1 ether * x ** 2 / a + b
     * @param b The value of b in the bonding curve formula 1 ether * x ** 2 / a + b
     * @param creatorFeeOn boolean specifying if creator fees are collected
     * @return The price to buy the given amount of cards
     */
    function getPriceToBuy(
        uint80 supply,
        uint80 amount,
        uint32 a,
        uint80 b,
        bool creatorFeeOn
    ) public view returns (uint256) {
        uint256 bondingCurvePrice = _getBondingCurvePrice(supply, amount, a, b);
        uint256 partyDaoFee = (bondingCurvePrice * partyDaoFeeBps) / BPS;
        uint256 treasuryFee = (bondingCurvePrice * treasuryFeeBps) / BPS;
        uint256 creatorFee = (bondingCurvePrice * (creatorFeeOn ? creatorFeeBps : 0)) / BPS;
        return bondingCurvePrice + partyDaoFee + treasuryFee + creatorFee;
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
        uint256 amount,
        uint32 a,
        uint80 b
    ) internal pure returns (uint256) {
        // Using the function 1 ether * x ** 2 / a + b
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
            uint256(a) +
            amount *
            uint256(b);
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
        (bool success, ) = PARTY_DAO.call{ value: _partyDaoFeeClaimable }("");
        if (!success) {
            revert EthTransferFailed();
        }
        emit PartyDaoFeesClaimed(_partyDaoFeeClaimable);
    }
}
