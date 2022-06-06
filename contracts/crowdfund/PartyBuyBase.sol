// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../tokens/IERC721.sol";
import "../party/Party.sol";
import "../utils/Implementation.sol";
import "../utils/LibSafeERC721.sol";
import "../utils/LibRawResult.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "./PartyCrowdfund.sol";

// Base for PartyBuy and PartyCollectionBuy
abstract contract PartyBuyBase is Implementation, PartyCrowdfund {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;
    using LibRawResult for bytes;

    struct PartyBuyBaseOptions {
        // The name of the crowdfund.
        // This will also carry over to the governance party.
        string name;
        // The token symbol for both the crowdfund and the governance NFTs.
        string symbol;
        // How long this crowdfund has to bid on the NFT, in seconds.
        uint40 duration;
        // Maximum amount this crowdfund will pay for the NFT.
        // If zero, no maximum.
        uint128 maximumPrice;
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

    event Won(Party party);

    error MaximumPriceError(uint128 callValue, uint128 maximumPrice);
    error NoContributionsError();
    error FailedToBuyNFTError(IERC721 token, uint256 tokenId);

    // When this crowdfund expires.
    uint40 public expiry;
    // Maximum amount this crowdfund will pay for the NFT.
    // If zero, no maximum.
    uint128 public maximumPrice;
    // What the NFT was actually bought for.
    uint128 public settledPrice;

    constructor(IGlobals globals) PartyCrowdfund(globals) {}

    function _initialize(PartyBuyBaseOptions memory opts)
        internal
    {
        PartyCrowdfund._initialize(PartyCrowdfundOptions({
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
        expiry = uint40(opts.duration + block.timestamp);
    }

    // Execute arbitrary calldata to perform a buy, creating a party
    // if it successfully buys the NFT.
    function _buy(
        IERC721 token,
        uint256 tokenId,
        address payable callTarget,
        uint128 callValue,
        bytes calldata callData,
        FixedGovernanceOpts memory governanceOpts
    )
        internal
    {
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc != CrowdfundLifecycle.Active) {
            revert WrongLifecycleError(lc);
        }
        {
            uint128 maximumPrice_ = maximumPrice;
            if (maximumPrice_ != 0 && callValue > maximumPrice_) {
                revert MaximumPriceError(callValue, maximumPrice);
            }
            // If the purchase would be free, everyone wins.
            uint128 settledPrice_ = callValue == 0 ? totalContributions : callValue;
            if (settledPrice_ == 0) {
                // Still zero, which means no contributions.
                revert NoContributionsError();
            }
            settledPrice = settledPrice_;
        }
        {
            (bool s, bytes memory r) = callTarget.call{ value: callValue }(callData);
            if (!s) {
                r.rawRevert();
            }
        }
        if (token.safeOwnerOf(tokenId) != address(this)) {
            revert FailedToBuyNFTError(token, tokenId);
        }
        emit Won(_createParty(governanceOpts, token, tokenId));
    }

    function getCrowdfundLifecycle() public override view returns (CrowdfundLifecycle) {
        // If there is a settled price then we tried to buy the NFT.
        if (settledPrice != 0) {
            return address(party) != address(0)
                // If we have a party, then we succeeded buying the NFT.
                ? CrowdfundLifecycle.Won
                // Otherwise we're in the middle of the buy().
                : CrowdfundLifecycle.Busy;
        }
        if (block.timestamp >= expiry) {
            // Expired but nothing to do so skip straight to lost.
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
