// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC20.sol";
import "../utils/LibAddress.sol";
import "../utils/LibERC20Compat.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibSafeCast.sol";

import "./ITokenDistributorParty.sol";

/// @notice Creates token distributions for parties.
contract TokenDistributor {
    using LibAddress for address payable;
    using LibERC20Compat for IERC20;
    using LibRawResult for bytes;
    using LibSafeCast for uint256;

    // Info on a distribution, created by createDistribution().
    struct DistributionInfo {
        // ID of the distribution. Assigned by createDistribution().
        uint256 distributionId;
        // The party whose members can claim the distribution.
        ITokenDistributorParty party;
        // Who can claim `fee`.
        address payable feeRecipient;
        // The token being distributed.
        IERC20 token;
        // Total amount of `token` that can be claimed by party members.
        uint128 memberSupply;
        // Amount of `token` to be redeemed by `feeRecipient`.
        uint128 fee;
    }

    struct DistributionState {
        // The remaining member supply.
        uint128 remainingMemberSupply;
        // The 15-byte hash of the DistributionInfo.
        bytes15 distributionHash15;
        // Whether partyDao has claimed its distribution share.
        bool wasFeeClaimed;
        // Whether a governance token has claimed its distribution share.
        mapping (uint256 => bool) hasTokenClaimed;
    }

    error OnlyPartyDaoError(address notDao, address partyDao);
    error OnlyPartyDaoAuthorityError(address notDaoAuthority);
    error InvalidDistributionInfoError(DistributionInfo info);
    error DistributionAlreadyClaimedByTokenError(uint256 distributionId, uint256 tokenId);
    error DistributionAlreadyClaimedByPartyDaoError(uint256 distributionId);
    error MustOwnTokenError(address sender, address expectedOwner, uint256 tokenId);
    error EmergencyActionsNotAllowed();
    error InvalidDistributionSupply(uint128 supply);
    error OnlyFeeRecipientError(address caller, address feeRecipient);
    error InvalidFeeBps(uint16 feeBps);

    event DistributionCreated(DistributionInfo info);
    event DistributionClaimedByPartyDao(DistributionInfo info, address recipient, uint256 amountClaimed);
    event DistributionClaimedByToken(DistributionInfo info, uint256 tokenId, address recipient, uint256 amountClaimed);

    IERC20 constant private ETH_TOKEN = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    IGlobals public immutable GLOBALS;

    /// @notice Whether the DAO can call emergency functions.
    bool public allowEmergencyActions = true;
    /// @notice Last distribution ID for a party.
    mapping(ITokenDistributorParty => uint256) public lastDistributionIdPerParty;
    /// Last known balance of a token.
    /// Gets lazily updated when creating and claiming a distribution (transfers).
    /// Allows one to simply transfer and call `createDistribution()` without
    /// fussing with allowances.
    mapping(IERC20 => uint256) private _storedBalances;
    // tokenDistributorParty => distributionId => DistributionState
    mapping(ITokenDistributorParty => mapping(uint256 => DistributionState)) private _distributionStates;

    // msg.sender == DAO
    modifier onlyPartyDao() {
        {
            address partyDao = GLOBALS.getAddress(LibGlobals.GLOBAL_DAO_WALLET);
            if (msg.sender != partyDao) {
                revert OnlyPartyDaoError(msg.sender, partyDao);
            }
        }
        _;
    }

    // allowEmergencyActions == true
    modifier onlyIfEmergencyActionsAllowed() {
        if (!allowEmergencyActions) {
            revert EmergencyActionsNotAllowed();
        }
        _;
    }

    constructor(IGlobals globals) {
        GLOBALS = globals;
    }

    /// @notice Create a new distribution for an outstanding token balance
    ///         governed by a party (msg.sender).
    ///         Tokens should be transferred directly into this contract
    ///         immediately prior (same tx) to calling createDistribution().
    ///         ETH can be attached to the createDistribution() call itself.
    // Tokens should be transferred into this contract before calling this
    // function. ETH can be attached to this call for ETH payouts.
    // The caller should implement the `ITokenDistributorParty` interface
    // (ie, be a `Party` instance).
    function createDistribution(IERC20 token, address payable feeRecipient, uint16 feeBps)
        external
        payable
        returns (DistributionInfo memory info)
    {
        if (feeBps > 1e4) {
            revert InvalidFeeBps(feeBps);
        }
        uint128 bal;
        if (token == ETH_TOKEN) { // Support native ETH.
            bal = address(this).balance.safeCastUint256ToUint128();
        } else {
            bal = token.balanceOf(address(this)).safeCastUint256ToUint128();
        }
        // Use the delta between actual balance _storedBalances as the
        // distribution supply.
        uint128 supply = bal - _storedBalances[token].safeCastUint256ToUint128();
        // Supply must be nonzero.
        if (supply == 0) {
            revert InvalidDistributionSupply(supply);
        }
        // Update stored balance.
        _storedBalances[token] = bal;

        // Create a distribution.
        ITokenDistributorParty party = ITokenDistributorParty(msg.sender);
        uint256 distId = ++lastDistributionIdPerParty[party];
        uint128 fee = supply * feeBps / 1e4;
        uint128 memberSupply = supply - fee;

        info = DistributionInfo({
            distributionId: distId,
            token: token,
            party: party,
            memberSupply: memberSupply,
            feeRecipient: feeRecipient,
            fee: fee
        });
        (
            _distributionStates[party][distId].distributionHash15,
            _distributionStates[party][distId].remainingMemberSupply
        ) = (_getDistributionHash(info), memberSupply);
        emit DistributionCreated(info);
    }

    /// @notice Claim a portion of a distribution owed to a `tokenId` belonging
    ///         to the party that created the distribution. The caller
    ///         must own this token.
    function claim(DistributionInfo calldata info, uint256 tokenId)
        external
        returns (uint256 amountClaimed)
    {
        // Caller must own the token.
        address ownerOfToken = info.party.ownerOf(tokenId);
        if (msg.sender != ownerOfToken) {
            revert MustOwnTokenError(msg.sender, ownerOfToken, tokenId);
        }
        // DistributionInfo must be correct for this distribution ID.
        DistributionState storage state = _distributionStates[info.party][info.distributionId];
        if (state.distributionHash15 != _getDistributionHash(info)) {
            revert InvalidDistributionInfoError(info);
        }
        // The tokenId must not have claimed its distribution yet.
        if (state.hasTokenClaimed[tokenId]) {
            revert DistributionAlreadyClaimedByTokenError(info.distributionId, tokenId);
        }
        // Mark the tokenId as having claimed their distribution.
        state.hasTokenClaimed[tokenId] = true;

        // Compute amount owed to tokenId.
        amountClaimed = getClaimAmount(info, tokenId);

        // Cap at the remaining member supply. Otherwise a malicious
        // party could drain more than the distribution supply.
        uint128 remainingMemberSupply = state.remainingMemberSupply;
        amountClaimed = amountClaimed > remainingMemberSupply
            ? remainingMemberSupply
            : amountClaimed;
        state.remainingMemberSupply =
            remainingMemberSupply - amountClaimed.safeCastUint256ToUint128();

        // Transfer tokens owed.
        _transfer(info.token, payable(ownerOfToken), amountClaimed);
        emit DistributionClaimedByToken(info, tokenId, ownerOfToken, amountClaimed);
    }

    /// @notice Compute the amount of a distribution's token owed to a party member,
    ///         identified by tokenId.
    function getClaimAmount(DistributionInfo calldata info, uint256 tokenId)
        public
        view
        returns (uint256)
    {
        // getDistributionShareOf() is the fraction of the memberSupply tokenId
        // is entitled to, scaled by 1e18.
        return info.party.getDistributionShareOf(tokenId) * info.memberSupply / 1e18;
    }

    /// @notice Claim the fee for a distribution. Only a distribution's feeRecipient
    ///         can call this.
    function claimFee(DistributionInfo calldata info, address payable recipient)
        external
    {
        // DistributionInfo must be correct for this distribution ID.
        DistributionState storage state = _distributionStates[info.party][info.distributionId];
        if (state.distributionHash15 != _getDistributionHash(info)) {
            revert InvalidDistributionInfoError(info);
        }
        // Caller must be the fee recipient.
        if (info.feeRecipient != msg.sender) {
            revert OnlyFeeRecipientError(msg.sender, info.feeRecipient);
        }
        // Must not have claimed the fee yet.
        if (state.wasFeeClaimed) {
            revert DistributionAlreadyClaimedByPartyDaoError(info.distributionId);
        }
        // Mark the fee as claimed.
        state.wasFeeClaimed = true;
        // Transfer the tokens owed.
        _transfer(info.token, recipient, info.fee);
        emit DistributionClaimedByPartyDao(info, recipient, info.fee);
    }

    /// @notice Check whether the fee has been claimed for a distribution.
    function wasFeeClaimed(ITokenDistributorParty party, uint256 distributionId)
        external
        view
        returns (bool)
    {
        return _distributionStates[party][distributionId].wasFeeClaimed;
    }

    /// @notice Check whether a tokenID has claimed their share of a distribution.
    function hasTokenIdClaimed(
        ITokenDistributorParty party,
        uint256 tokenId,
        uint256 distributionId
    )
        external
        view returns (bool)
    {
        return _distributionStates[party][distributionId].hasTokenClaimed[tokenId];
    }

    /// @notice Get how much unclaimed member tokens are left in a distribution.
    function getRemainingMemberSupply(
        ITokenDistributorParty party,
        uint256 distributionId
    )
        public
        view
        returns (uint256)
    {
        return _distributionStates[party][distributionId].remainingMemberSupply;
    }

    function emergencyRemoveDistribution(
        ITokenDistributorParty party,
        uint256 distributionId
    )
        onlyPartyDao
        onlyIfEmergencyActionsAllowed
        public
    {
        delete _distributionStates[party][distributionId];
    }

    function emergencyWithdraw(
        IERC20 token,
        address payable recipient,
        uint256 amount
    )
        onlyPartyDao
        onlyIfEmergencyActionsAllowed
        public
    {
        _transfer(token, recipient, amount);
    }

    function disableEmergencyActions() onlyPartyDao public {
        allowEmergencyActions = false;
    }

    // For receiving ETH
    receive() external payable {}

    function _transfer(IERC20 token, address payable recipient, uint256 amount)
        private
    {
        // Reduce stored token balance.
        _storedBalances[token] -= amount;
        if (token == ETH_TOKEN) {
            recipient.transferEth(amount);
        } else {
            token.compatTransfer(recipient, amount);
        }
    }

    function _getDistributionHash(DistributionInfo memory info)
        private
        pure
        returns (bytes15 hash)
    {
        assembly {
            hash := and(
                keccak256(info, 0xC0),
                0xffffffffffffffffffffffffffffff0000000000000000000000000000000000
            )
        }
    }
}
