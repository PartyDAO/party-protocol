// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.20;

import "openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./AuctionCrowdfundBase.sol";

/// @notice A crowdfund that can repeatedly bid on auctions for an NFT from a
///         specific collection on a specific market (e.g. Nouns) and can
///         continue bidding on new auctions until it wins.
contract RollingAuctionCrowdfund is AuctionCrowdfundBase {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;
    using LibRawResult for bytes;

    struct RollOverArgs {
        // The `tokenId` of the next NFT to bid on in the next auction.
        // Only used if the crowdfund lost the current auction.
        uint256 nextNftTokenId;
        // The `auctionId` of the the next auction. Only used if the
        // crowdfund lost the current auction.
        uint256 nextAuctionId;
        // The maximum bid the party can place for the next auction.
        // Only used if the crowdfund lost the current auction.
        uint96 nextMaximumBid;
        // The Merkle proof used to verify that `nextAuctionId` and
        // `nextNftTokenId` are allowed. Only used if the crowdfund
        // lost the current auction.
        bytes32[] proof;
        // If the caller is a host, this is the index of the caller in the
        // `governanceOpts.hosts` array. Only used if the crowdfund lost the
        // current auction AND host are allowed to choose any next auction.
        uint256 hostIndex;
    }

    event AuctionUpdated(uint256 nextNftTokenId, uint256 nextAuctionId, uint256 nextMaximumBid);

    error BadNextAuctionError();

    /// @notice Merkle root of list of allowed next auctions that can be rolled
    ///         over to if the current auction loses. Each leaf should be hashed
    ///         as `keccak256(abi.encodePacked(auctionId, tokenId)))` where
    ///         `auctionId` is the auction ID of the auction to allow and
    ///         `tokenId` is the `tokenId` of the NFT being auctioned.
    bytes32 public allowedAuctionsMerkleRoot;

    // Set the `Globals` contract.
    constructor(IGlobals globals) AuctionCrowdfundBase(globals) {}

    /// @notice Initializer to be delegatecalled by `Proxy` constructor. Will
    ///         revert if called outside the constructor.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    /// @param allowedAuctionsMerkleRoot_ Merkle root of list of allowed next
    ///                                   auctions that can be rolled over to
    ///                                   if the current auction loses.
    function initialize(
        AuctionCrowdfundBase.AuctionCrowdfundOptions memory opts,
        bytes32 allowedAuctionsMerkleRoot_
    ) external payable onlyInitialize {
        // Initialize the base contract.
        AuctionCrowdfundBase._initialize(opts);

        // Set the merkle root of allowed auctions.
        allowedAuctionsMerkleRoot = allowedAuctionsMerkleRoot_;
    }

    /// @notice Calls `finalize()` on the market adapter, which will claim the NFT
    ///         (if necessary) if we won, or recover our bid (if necessary)
    ///         if the crowfund expired and we lost the current auction. If we
    ///         lost but the crowdfund has not expired, this will revert. Only
    ///         call this to finalize the result of a won or expired crowdfund,
    ///         otherwise call `finalizeOrRollOver()`.
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
        // Empty args because we don't need to roll over to another auction.
        RollOverArgs memory args;

        // If the crowdfund won, only `governanceOpts` is relevant. The rest are ignored.
        return finalizeOrRollOver(args, governanceOpts, proposalEngineOpts);
    }

    /// @notice Calls `finalize()` on the market adapter, which will claim the NFT
    ///         (if necessary) if we won, or recover our bid (if necessary)
    ///         if the crowfund expired and we lost. If we lost but the
    ///         crowdfund has not expired, it will move on to the next auction
    ///         specified (if allowed).
    /// @param args Arguments used to roll over to the next auction if the
    ///             crowdfund lost the current auction.
    /// @param governanceOpts The options used to initialize governance in the
    ///                       `Party` instance created if the crowdfund wins.
    /// @param proposalEngineOpts The options used to initialize the proposal
    ///                           engine in the `Party` instance created if the
    ///                           crowdfund wins.
    /// @param party_ Address of the `Party` instance created if successful.
    function finalizeOrRollOver(
        RollOverArgs memory args,
        FixedGovernanceOpts memory governanceOpts,
        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts
    ) public onlyDelegateCall returns (Party party_) {
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
            // Create a governance party around the NFT.
            party_ = _createParty(
                governanceOpts,
                proposalEngineOpts,
                false,
                nftContract,
                nftTokenId
            );
            emit Won(lastBid, party_);
            // Notify third-party platforms that the crowdfund NFT metadata has
            // updated for all tokens.
            emit BatchMetadataUpdate(0, type(uint256).max);

            _bidStatus = AuctionCrowdfundStatus.Finalized;
        } else if (lc == CrowdfundLifecycle.Expired) {
            // Crowdfund expired without NFT; finalize a loss.

            // Clear `lastBid` so `_getFinalPrice()` is 0 and people can redeem their
            // full contributions when they burn their participation NFTs.
            lastBid = 0;
            emit Lost();
            // Notify third-party platforms that the crowdfund NFT metadata has
            // updated for all tokens.
            emit BatchMetadataUpdate(0, type(uint256).max);

            _bidStatus = AuctionCrowdfundStatus.Finalized;
        } else {
            // Move on to the next auction if this one has been lost (or, in
            // rare cases, if the NFT was acquired for free and funds remain
            // unused).

            if (allowedAuctionsMerkleRoot != bytes32(0)) {
                // Check that the next `auctionId` and `tokenId` for the next
                // auction to roll over have been allowed.
                if (
                    !MerkleProof.verify(
                        args.proof,
                        allowedAuctionsMerkleRoot,
                        // Hash leaf with extra (empty) 32 bytes to prevent a second
                        // preimage attack by hashing >64 bytes.
                        keccak256(
                            abi.encodePacked(bytes32(0), args.nextAuctionId, args.nextNftTokenId)
                        )
                    )
                ) {
                    revert BadNextAuctionError();
                }
            } else {
                // Let the host change to any next auction.
                _assertIsHost(msg.sender, governanceOpts, proposalEngineOpts, args.hostIndex);
            }

            // Check that the new auction can be bid on and is valid.
            _validateAuction(market, args.nextAuctionId, nftContract, args.nextNftTokenId);

            // Check that the next maximum bid is greater than the auction's minimum bid.
            uint256 minimumBid = market.getMinimumBid(args.nextAuctionId);
            if (args.nextMaximumBid < minimumBid) {
                revert MinimumBidExceedsMaximumBidError(minimumBid, args.nextMaximumBid);
            }

            // Update state for next auction.
            nftTokenId = args.nextNftTokenId;
            auctionId = args.nextAuctionId;
            maximumBid = args.nextMaximumBid;
            lastBid = 0;

            emit AuctionUpdated(args.nextNftTokenId, args.nextAuctionId, args.nextMaximumBid);

            // Change back the auction status from `Busy` to `Active`.
            _bidStatus = AuctionCrowdfundStatus.Active;
        }
    }
}
