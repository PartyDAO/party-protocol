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
        uint256 erc1155TokenId;
        // Total amount of `token` that can be claimed by party members.
        uint128 memberSupply;
        // Amount of `token` to be redeemed by `feeRecipient`.
        uint128 fee;
    }

    event DistributionCreated(
        ITokenDistributorParty indexed party,
        DistributionInfo info,
        bytes15 distributionHash15
    );
    event DistributionFeeClaimed(
        ITokenDistributorParty indexed party,
        address indexed feeRecipient,
        TokenType tokenType,
        address token,
        uint256 erc1155TokenId,
        uint256 amount
    );
    event DistributionClaimedByPartyToken(
        ITokenDistributorParty indexed party,
        uint256 indexed partyTokenId ,
        address indexed owner,
        TokenType tokenType,
        address token,
        uint256 erc1155TokenId,
        uint256 amountClaimed
    );

    /// @notice Create a new distribution for an outstanding native token balance
    ///         governed by a party.
    /// @dev Native tokens should be transferred directly into this contract
    ///      immediately prior (same tx) to calling createDistribution() or
    ///      attached to the call itself.
    function createNativeDistribution(
        ITokenDistributorParty party,
        address payable feeRecipient,
        uint16 feeBps
    )
        external
        payable
        returns (DistributionInfo memory info);

    /// @notice Create a new distribution for an outstanding ERC20 token balance
    ///         governed by a party.
    /// @dev ERC20 tokens should be transferred directly into this contract
    ///      immediately prior (same tx) to calling createDistribution() or
    ///      attached to the call itself.
    function createErc20Distribution(
        IERC20 token,
        ITokenDistributorParty party,
        address payable feeRecipient,
        uint16 feeBps
    )
        external
        returns (DistributionInfo memory info);

    /// @notice Create a new distribution for an outstanding ERC1155 token balance
    ///         governed by a party.
    /// @dev ERC1155 tokens should be transferred directly into this contract
    ///      immediately prior (same tx) to calling createDistribution() or
    ///      attached to the call itself.
    function createErc1155Distribution(
        IERC1155 token,
        uint256 tokenId,
        ITokenDistributorParty party,
        address payable feeRecipient,
        uint16 feeBps
    )
        external
        returns (DistributionInfo memory info);

    /// @notice Claim a portion of a distribution owed to a `partyTokenId` belonging
    ///         to the party that created the distribution. The caller
    ///         must own this token.
    function claim(DistributionInfo calldata info, uint256 partyTokenId)
        external
        returns (uint128 amountClaimed);

    /// @notice Claim the fee for a distribution. Only a distribution's feeRecipient
    ///         can call this.
    function claimFee(DistributionInfo calldata info, address payable recipient)
        external;

    /// @notice Batch version of claim().
    function batchClaim(DistributionInfo[] calldata infos, uint256[] calldata partyTokenIds)
        external
        returns (uint128[] memory amountsClaimed);

    /// @notice Batch version of claimFee().
    function batchClaimFee(DistributionInfo[] calldata infos, address payable[] calldata recipients)
        external;

    /// @notice Compute the amount of a distribution's token owed to a party member,
    ///         identified by tokenId.
    function getClaimAmount(
        ITokenDistributorParty party,
        uint256 memberSupply,
        uint256 partyTokenId
    )
        external
        view
        returns (uint128);

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
        returns (uint128);
}
