// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
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
    using LibRawResult for bytes;

    struct BuyCrowdfundBaseOptions {
        // The name of the crowdfund.
        // This will also carry over to the governance party.
        string name;
        // The token symbol for both the crowdfund and the governance NFTs.
        string symbol;
        // How long this crowdfund has to bid on the NFT, in seconds.
        uint40 duration;
        // Maximum amount this crowdfund will pay for the NFT.
        // If zero, no maximum.
        uint96 maximumPrice;
        // An address that receieves an extra share of the final voting power
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
        // The gatekeeper contract to use (if non-null) to restrict who can
        // contribute to this crowdfund.
        IGateKeeper gateKeeper;
        // The gatekeeper contract to use (if non-null).
        bytes12 gateKeeperId;
        // Governance options.
        FixedGovernanceOpts governanceOpts;
    }

    event Won(Party party, IERC721 token, uint256 tokenId, uint256 settledPrice);
    event Lost();

    error MaximumPriceError(uint96 callValue, uint96 maximumPrice);
    error NoContributionsError();
    error FailedToBuyNFTError(IERC721 token, uint256 tokenId);
    error InvalidCallTargetError(address callTarget);

    /// @notice When this crowdfund expires.
    uint40 public expiry;
    /// @notice Maximum amount this crowdfund will pay for the NFT. If zero, no maximum.
    uint96 public maximumPrice;
    /// @notice What the NFT was actually bought for.
    uint96 public settledPrice;

    // Set the `Globals` contract.
    constructor(IGlobals globals) Crowdfund(globals) {}

    // Initialize storage for proxy contracts.
    function _initialize(BuyCrowdfundBaseOptions memory opts)
        internal
    {
        expiry = uint40(opts.duration + block.timestamp);
        maximumPrice = opts.maximumPrice;
        Crowdfund._initialize(CrowdfundOptions({
            name: opts.name,
            symbol: opts.symbol,
            splitRecipient: opts.splitRecipient,
            splitBps: opts.splitBps,
            initialContributor: opts.initialContributor,
            initialDelegate: opts.initialDelegate,
            gateKeeper: opts.gateKeeper,
            gateKeeperId: opts.gateKeeperId,
            governanceOpts: opts.governanceOpts
        }));
    }

    // Execute arbitrary calldata to perform a buy, creating a party
    // if it successfully buys the NFT.
    function _buy(
        IERC721 token,
        uint256 tokenId,
        address payable callTarget,
        uint96 callValue,
        bytes calldata callData,
        FixedGovernanceOpts memory governanceOpts,
        bool isValidatedGovernanceOpts
    )
        internal
        onlyDelegateCall
        returns (Party party_)
    {
        // Ensure the call target isn't trying to reenter
        if (callTarget == address(this)) {
            revert InvalidCallTargetError(callTarget);
        }
        // Check that the crowdfund is still active.
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc != CrowdfundLifecycle.Active) {
            revert WrongLifecycleError(lc);
        }
        uint96 totalContributions_ = totalContributions;
        // Prevent unaccounted ETH from being used to inflate the price and
        // create "ghost shares" in voting power.
        if (callValue > totalContributions_) {
            revert ExceedsTotalContributionsError(callValue, totalContributions_);
        }
        {
            uint96 maximumPrice_ = maximumPrice;
            if (maximumPrice_ != 0 && callValue > maximumPrice_) {
                revert MaximumPriceError(callValue, maximumPrice);
            }
        }
        // Temporarily set to non-zero as a reentrancy guard.
        settledPrice = type(uint96).max;
        {
            // Execute the call to buy the NFT.
            (bool s, bytes memory r) = callTarget.call{ value: callValue }(callData);
            if (!s) {
                r.rawRevert();
            }
        }
        // Make sure we acquired the NFT we want.
        if (token.safeOwnerOf(tokenId) == address(this)) {
            if (address(this).balance >= totalContributions_) {
                // If the purchase was free or the NFT was "gifted" to us,
                // refund all contributors by declaring we lost.
                settledPrice = 0;
                expiry = 0;
                emit Lost();
            } else {
                settledPrice = callValue;
                emit Won(
                    // Create a party around the newly bought NFT.
                    party_ = _createParty(
                        governanceOpts,
                        isValidatedGovernanceOpts,
                        token,
                        tokenId
                    ),
                    token,
                    tokenId,
                    callValue
                );
            }
        } else {
            revert FailedToBuyNFTError(token, tokenId);
        }
    }

    /// @inheritdoc Crowdfund
    function getCrowdfundLifecycle() public override view returns (CrowdfundLifecycle) {
        // If there is a settled price then we tried to buy the NFT.
        if (settledPrice != 0) {
            return address(party) != address(0)
                // If we have a party, then we succeeded buying the NFT.
                ? CrowdfundLifecycle.Won
                // Otherwise we're in the middle of the `buy()`.
                : CrowdfundLifecycle.Busy;
        }
        if (block.timestamp >= expiry) {
            // Expired, but nothing to do so skip straight to lost, or NFT was
            // acquired for free so refund contributors and trigger lost.
            return CrowdfundLifecycle.Lost;
        }
        return CrowdfundLifecycle.Active;
    }

    function _getFinalPrice()
        internal
        override
        view
        returns (uint256)
    {
        return settledPrice;
    }
}
