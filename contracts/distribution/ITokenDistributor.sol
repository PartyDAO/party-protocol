// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../tokens/IERC20.sol";
import "../tokens/IERC1155.sol";

import "./ITokenDistributorParty.sol";

/// @notice Creates token distributions for parties.
interface ITokenDistributor {
    enum TokenType {
        Native,
        Erc20,
        Erc1155
    }

    // Info on a distribution, created by createDistribution().
    struct DistributionInfo {
        // Type of distribution/token.
        TokenType tokenType;
        // ID of the distribution. Assigned by createDistribution().
        uint256 distributionId;
        // The party whose members can claim the distribution.
        ITokenDistributorParty party;
        // Who can claim `fee`.
        address payable feeRecipient;
        // The token being distributed.
        address token;
        // For 1155s, the token ID. Zero for every other type.
        uint256 tokenId;
        // Total amount of `token` that can be claimed by party members.
        uint128 memberSupply;
        // Amount of `token` to be redeemed by `feeRecipient`.
        uint128 fee;
    }

    error OnlyPartyDaoError(address notDao, address partyDao);
    error OnlyPartyDaoAuthorityError(address notDaoAuthority);
    error InvalidDistributionInfoError(DistributionInfo info);
    error DistributionAlreadyClaimedByTokenError(uint256 distributionId, uint256 tokenId);
    error DistributionFeeAlreadyClaimedError(uint256 distributionId);
    error MustOwnTokenError(address sender, address expectedOwner, uint256 tokenId);
    error EmergencyActionsNotAllowed();
    error InvalidDistributionSupply(uint128 supply);
    error OnlyFeeRecipientError(address caller, address feeRecipient);
    error InvalidFeeBps(uint16 feeBps);

    event DistributionCreated(DistributionInfo info);
    event DistributionClaimedByPartyDao(DistributionInfo info, address recipient, uint256 amountClaimed);
    event DistributionClaimedByToken(DistributionInfo info, uint256 tokenId, address recipient, uint256 amountClaimed);

    /// @notice Create a new distribution for an outstanding native token balance
    ///         governed by a party (msg.sender).
    /// @dev Native tokens should be transferred directly into this contract
    ///      immediately prior (same tx) to calling createDistribution() or
    ///      attached to the call itself.
    ///      The caller should implement the `ITokenDistributorParty` interface
    ///      (ie, be a `Party` instance).
    function createNativeDistribution(address payable feeRecipient, uint16 feeBps)
        external
        payable
        returns (DistributionInfo memory info);

    /// @notice Create a new distribution for an outstanding ERC20 token balance
    ///         governed by a party (msg.sender).
    /// @dev ERC20 tokens should be transferred directly into this contract
    ///      immediately prior (same tx) to calling createDistribution() or
    ///      attached to the call itself.
    ///      The caller should implement the `ITokenDistributorParty` interface
    ///      (ie, be a `Party` instance).
    function createErc20Distribution(
        IERC20 token,
        address payable feeRecipient,
        uint16 feeBps
    )
        external
        returns (DistributionInfo memory info);

    /// @notice Create a new distribution for an outstanding ERC1155 token balance
    ///         governed by a party (msg.sender).
    /// @dev ERC1155 tokens should be transferred directly into this contract
    ///      immediately prior (same tx) to calling createDistribution() or
    ///      attached to the call itself.
    ///      The caller should implement the `ITokenDistributorParty` interface
    ///      (ie, be a `Party` instance).
    function createErc1155Distribution(
        IERC1155 token,
        uint256 tokenId,
        address payable feeRecipient,
        uint16 feeBps
    )
        external
        returns (DistributionInfo memory info);

    /// @notice Claim a portion of a distribution owed to a `tokenId` belonging
    ///         to the party that created the distribution. The caller
    ///         must own this token.
    function claim(DistributionInfo calldata info, uint256 partyTokenId)
        external
        returns (uint256 amountClaimed);

    /// @notice Claim the fee for a distribution. Only a distribution's feeRecipient
    ///         can call this.
    function claimFee(DistributionInfo calldata info, address payable recipient)
        external;

    /// @notice Compute the amount of a distribution's token owed to a party member,
    ///         identified by tokenId.
    function getClaimAmount(DistributionInfo calldata info, uint256 tokenId)
        external
        view
        returns (uint256);

    /// @notice Check whether the fee has been claimed for a distribution.
    function wasFeeClaimed(ITokenDistributorParty party, uint256 distributionId)
        external
        view
        returns (bool);

    /// @notice Check whether a party tokenId has claimed their share of a distribution.
    function hasPartyTokenIdClaimed(
        ITokenDistributorParty party,
        uint256 partyTokenId,
        uint256 distributionId
    )
        external
        view returns (bool);

    /// @notice Get how much unclaimed member tokens are left in a distribution.
    function getRemainingMemberSupply(
        ITokenDistributorParty party,
        uint256 distributionId
    )
        external
        view
        returns (uint256);

    /// @notice DAO-only function to clear a distribution in case something goes wrong.
    function emergencyRemoveDistribution(
        ITokenDistributorParty party,
        uint256 distributionId
    )
        external;

    /// @notice DAO-only function to withdraw tokens in case something goes wrong.
    function emergencyWithdraw(
        TokenType tokenType,
        address token,
        uint256 tokenId,
        address payable recipient,
        uint256 amount
    )
        external;

    function disableEmergencyActions() external;
}
