// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./AuctionCrowdfundBase.sol";

/// @notice A crowdfund that can repeatedly bid on an auction for a specific NFT
///         (i.e. with a known token ID) until it wins.
contract AuctionCrowdfund is AuctionCrowdfundBase {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;
    using LibRawResult for bytes;

    // Set the `Globals` contract.
    constructor(IGlobals globals) AuctionCrowdfundBase(globals) {}

    /// @notice Initializer to be delegatecalled by `Proxy` constructor. Will
    ///         revert if called outside the constructor.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    function initialize(AuctionCrowdfundOptions memory opts) external payable onlyConstructor {
        AuctionCrowdfundBase._initialize(opts);
    }

    /// @notice Calls `finalize()` on the market adapter, which will claim the NFT
    ///         (if necessary) if the crowdfund won, or recover the bid (if
    ///         necessary) if lost. If won, a party will also be created.
    /// @param governanceOpts The options used to initialize governance in the
    ///                       `Party` instance created if the crowdfund wins.
    /// @param proposalEngineOpts The options used to initialize the proposal
    ///                           engine in the `Party` instance created if the
    ///                           crowdfund wins.
    /// @return party_ Address of the `Party` instance created if successful.
    function finalize(
        FixedGovernanceOpts memory governanceOpts,
        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts
    ) external onlyDelegateCall returns (Party party_) {
        // Check that the auction is still active and has not passed the `expiry` time.
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc != CrowdfundLifecycle.Active && lc != CrowdfundLifecycle.Expired) {
            revert WrongLifecycleError(lc);
        }

        // Finalize the auction if it is not already finalized.
        uint96 lastBid_ = lastBid;
        _finalizeAuction(lc, market, auctionId, lastBid_);

        IERC721 nftContract_ = nftContract;
        uint256 nftTokenId_ = nftTokenId;
        // Are we now in possession of the NFT?
        if (nftContract_.safeOwnerOf(nftTokenId_) == address(this) && lastBid_ != 0) {
            // If we placed a bid before then consider it won for that price.
            // Create a governance party around the NFT.
            party_ = _createParty(
                governanceOpts,
                proposalEngineOpts,
                false,
                nftContract_,
                nftTokenId_
            );
            emit Won(lastBid_, party_);
        } else {
            // Otherwise we lost the auction or the NFT was gifted to us.
            // Clear `lastBid` so `_getFinalPrice()` is 0 and people can redeem their
            // full contributions when they burn their participation NFTs.
            lastBid = 0;
            emit Lost();
        }
        _bidStatus = AuctionCrowdfundStatus.Finalized;

        // Notify third-party platforms that the crowdfund NFT metadata has
        // updated for all tokens.
        emit BatchMetadataUpdate(0, type(uint256).max);
    }
}
