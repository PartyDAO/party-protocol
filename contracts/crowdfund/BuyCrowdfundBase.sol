// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../tokens/IERC721.sol";
import "../party/Party.sol";
import "../utils/Implementation.sol";
import "../utils/LibSafeERC721.sol";
import "../utils/LibRawResult.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "./Crowdfund.sol";

// Base for BuyCrowdfund and CollectionBuyCrowdfund
abstract contract BuyCrowdfundBase is Crowdfund {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;

    struct BuyCrowdfundBaseOptions {
        // The name of the crowdfund.
        // This will also carry over to the governance party.
        string name;
        // The token symbol for both the crowdfund and the governance NFTs.
        string symbol;
        // Customization preset ID to use for the crowdfund and governance NFTs.
        uint256 customizationPresetId;
        // How long this crowdfund has to buy the NFT, in seconds.
        uint40 duration;
        // Maximum amount this crowdfund will pay for the NFT.
        uint96 maximumPrice;
        // An address that receives an extra share of the final voting power
        // when the party transitions into governance.
        address payable splitRecipient;
        // What percentage (in bps) of the final total voting power `splitRecipient`
        // receives.
        uint16 splitBps;
        // If ETH is attached during deployment, it will be interpreted
        // as a contribution. This is who gets credit for that contribution.
        address initialContributor;
        // If there is an initial contribution, this is who they will delegate their
        // voting power to when the crowdfund transitions to governance.
        address initialDelegate;
        // Minimum amount of ETH that can be contributed to this crowdfund per address.
        uint96 minContribution;
        // Maximum amount of ETH that can be contributed to this crowdfund per address.
        uint96 maxContribution;
        // The gatekeeper contract to use (if non-null) to restrict who can
        // contribute to this crowdfund.
        IGateKeeper gateKeeper;
        // The gatekeeper contract to use (if non-null).
        bytes12 gateKeeperId;
        // Governance options.
        FixedGovernanceOpts governanceOpts;
    }

    event Won(Party party, IERC721[] tokens, uint256[] tokenIds, uint256 settledPrice);
    event Lost();

    error MaximumPriceError(uint96 callValue, uint96 maximumPrice);
    error NoContributionsError();
    error CallProhibitedError(address target, bytes data);
    error FailedToBuyNFTError(IERC721 token, uint256 tokenId);

    /// @notice When this crowdfund expires.
    uint40 public expiry;
    /// @notice Maximum amount this crowdfund will pay for the NFT.
    uint96 public maximumPrice;
    /// @notice What the NFT was actually bought for.
    uint96 public settledPrice;

    // Set the `Globals` contract.
    constructor(IGlobals globals) Crowdfund(globals) {}

    // Initialize storage for proxy contracts.
    function _initialize(BuyCrowdfundBaseOptions memory opts) internal {
        expiry = uint40(opts.duration + block.timestamp);
        maximumPrice = opts.maximumPrice;
        Crowdfund._initialize(
            CrowdfundOptions({
                name: opts.name,
                symbol: opts.symbol,
                customizationPresetId: opts.customizationPresetId,
                splitRecipient: opts.splitRecipient,
                splitBps: opts.splitBps,
                initialContributor: opts.initialContributor,
                initialDelegate: opts.initialDelegate,
                minContribution: opts.minContribution,
                maxContribution: opts.maxContribution,
                gateKeeper: opts.gateKeeper,
                gateKeeperId: opts.gateKeeperId,
                governanceOpts: opts.governanceOpts
            })
        );
    }

    // Execute arbitrary calldata to perform a buy, creating a party
    // if it successfully buys the NFT.
    function _buy(
        IERC721 token,
        uint256 tokenId,
        address payable callTarget,
        uint96 callValue,
        bytes memory callData
    ) internal returns (bool success, bytes memory revertData) {
        // Check that the call is not prohibited.
        if (!_isCallAllowed(callTarget, callData, token)) {
            revert CallProhibitedError(callTarget, callData);
        }
        // Check that the call value is under the maximum price.
        {
            uint96 maximumPrice_ = maximumPrice;
            if (callValue > maximumPrice_) {
                revert MaximumPriceError(callValue, maximumPrice_);
            }
        }
        // Execute the call to buy the NFT.
        (bool s, bytes memory r) = callTarget.call{ value: callValue }(callData);
        if (!s) {
            return (false, r);
        }
        // Return whether the NFT was successfully bought.
        return (token.safeOwnerOf(tokenId) == address(this), "");
    }

    function _finalize(
        IERC721[] memory tokens,
        uint256[] memory tokenIds,
        uint96 totalEthUsed,
        FixedGovernanceOpts memory governanceOpts,
        bool isValidatedGovernanceOpts
    ) internal returns (Party party_) {
        {
            // Prevent unaccounted ETH from being used to inflate the price and
            // create "ghost shares" in voting power.
            uint96 totalContributions_ = totalContributions;
            if (totalEthUsed > totalContributions_) {
                revert ExceedsTotalContributionsError(totalEthUsed, totalContributions_);
            }
        }
        if (totalEthUsed != 0) {
            // Create a party around the newly bought NFTs and finalize a win.
            settledPrice = totalEthUsed;
            party_ = _createParty(governanceOpts, isValidatedGovernanceOpts, tokens, tokenIds);
            emit Won(party_, tokens, tokenIds, totalEthUsed);
        } else {
            // If all NFTs were purchased for free or were all "gifted" to us,
            // refund all contributors by finalizing a loss.
            settledPrice = 0;
            expiry = uint40(block.timestamp);
            emit Lost();
        }
    }

    function _finalize(
        IERC721 token,
        uint256 tokenId,
        uint96 totalEthUsed,
        FixedGovernanceOpts memory governanceOpts,
        bool isValidatedGovernanceOpts
    ) internal returns (Party party_) {
        IERC721[] memory tokens = new IERC721[](1);
        tokens[0] = token;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        return _finalize(tokens, tokenIds, totalEthUsed, governanceOpts, isValidatedGovernanceOpts);
    }

    /// @inheritdoc Crowdfund
    function getCrowdfundLifecycle() public view override returns (CrowdfundLifecycle) {
        // If there is a settled price then we tried to buy the NFT.
        if (settledPrice != 0) {
            return
                address(party) != address(0)
                    ? CrowdfundLifecycle.Won // If we have a party, then we succeeded buying the NFT.
                    : CrowdfundLifecycle.Busy; // Otherwise we're in the middle of the `buy()`.
        }
        if (block.timestamp >= expiry) {
            // Expired, but nothing to do so skip straight to lost, or NFT was
            // acquired for free so refund contributors and trigger lost.
            return CrowdfundLifecycle.Lost;
        }
        return CrowdfundLifecycle.Active;
    }

    function _getFinalPrice() internal view override returns (uint256) {
        return settledPrice;
    }

    function _isCallAllowed(
        address payable callTarget,
        bytes memory callData,
        IERC721 token
    ) private view returns (bool isAllowed) {
        // Ensure the call target isn't trying to reenter
        if (callTarget == address(this)) {
            return false;
        }
        if (callTarget == address(token) && callData.length >= 4) {
            // Get the function selector of the call (first 4 bytes of calldata).
            bytes4 selector;
            assembly {
                selector := and(
                    mload(add(callData, 32)),
                    0xffffffff00000000000000000000000000000000000000000000000000000000
                )
            }
            // Prevent approving the NFT to be transferred out from the crowdfund.
            if (
                selector == IERC721.approve.selector ||
                selector == IERC721.setApprovalForAll.selector
            ) {
                return false;
            }
        }
        // All other calls are allowed.
        return true;
    }
}
