// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.17;

import "openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./AuctionCrowdfundBase.sol";

/// @notice A crowdfund that can repeatedly bid on auctions for an NFT from a
///         specific collection on a specific market (eg. Nouns) and can
///         continue bidding on new auctions until it wins.
contract RollingAuctionCrowdfund is AuctionCrowdfundBase {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;
    using LibRawResult for bytes;

    struct RollingAuctionCrowdfundOptions {
        // The name of the crowdfund.
        // This will also carry over to the governance party.
        string name;
        // The token symbol for both the crowdfund and the governance NFTs.
        string symbol;
        // Customization preset ID to use for the crowdfund and governance NFTs.
        uint256 customizationPresetId;
        // The auction ID (specific to the IMarketWrapper).
        uint256 auctionId;
        // IMarketWrapper contract that handles interactions with auction markets.
        IMarketWrapper market;
        // The ERC721 contract of the NFT being bought.
        IERC721 nftContract;
        // ID of the NFT being bought.
        uint256 nftTokenId;
        // How long this crowdfund has to bid on the NFT, in seconds.
        uint40 duration;
        // Maximum bid allowed per auction.
        uint96 maximumBid;
        // An address that receives a portion of the final voting power
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
        // The gate ID within the gateKeeper contract to use.
        bytes12 gateKeeperId;
        // Whether the party is only allowing a host to call `bid()`.
        bool onlyHostCanBid;
        // Merkle root of list of allowed next auctions that can be rolled over
        // to if the current auction loses. Each leaf should be hashed as
        // `keccak256(abi.encodePacked(bytes32(0), auctionId, tokenId)))` where `auctionId`
        // is the auction ID of the auction to allow and `tokenId` is the
        // `tokenId` of the NFT being auctioned.
        bytes32 allowedAuctionsMerkleRoot;
        // Fixed governance options (i.e. cannot be changed) that the governance
        // `Party` will be created with if the crowdfund succeeds.
        FixedGovernanceOpts governanceOpts;
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
    function initialize(
        RollingAuctionCrowdfundOptions memory opts
    ) external payable onlyConstructor {
        // Initialize the base contract.
        AuctionCrowdfundBase._initialize(
            AuctionCrowdfundBase.AuctionCrowdfundOptions({
                name: opts.name,
                symbol: opts.symbol,
                customizationPresetId: opts.customizationPresetId,
                auctionId: opts.auctionId,
                market: opts.market,
                nftContract: opts.nftContract,
                nftTokenId: opts.nftTokenId,
                duration: opts.duration,
                maximumBid: opts.maximumBid,
                splitRecipient: opts.splitRecipient,
                splitBps: opts.splitBps,
                initialContributor: opts.initialContributor,
                initialDelegate: opts.initialDelegate,
                minContribution: opts.minContribution,
                maxContribution: opts.maxContribution,
                gateKeeper: opts.gateKeeper,
                gateKeeperId: opts.gateKeeperId,
                onlyHostCanBid: opts.onlyHostCanBid,
                governanceOpts: opts.governanceOpts
            })
        );

        allowedAuctionsMerkleRoot = opts.allowedAuctionsMerkleRoot;
    }

    /// @notice Calls `finalize()` on the market adapter, which will claim the NFT
    ///         (if necessary) if we won, or recover our bid (if necessary)
    ///         if the crowfund expired and we lost the current auction. If we
    ///         lost but the crowdfund has not expired, this will revert. Only
    ///         call this to finalize the result of a won or expired crowdfund,
    ///         otherwise call `finalizeOrRollOver()`.
    /// @param governanceOpts The options used to initialize governance in the
    ///                       `Party` instance created if the crowdfund wins.
    /// @return party_ Address of the `Party` instance created if successful.
    function finalize(
        FixedGovernanceOpts memory governanceOpts
    ) external onlyDelegateCall returns (Party party_) {
        // If the crowdfund won, only `governanceOpts` is relevant. The rest are ignored.
        return finalizeOrRollOver(0, 0, 0, new bytes32[](0), governanceOpts, 0);
    }

    /// @notice Calls `finalize()` on the market adapter, which will claim the NFT
    ///         (if necessary) if we won, or recover our bid (if necessary)
    ///         if the crowfund expired and we lost. If we lost but the
    ///         crowdfund has not expired, it will move on to the next auction
    ///         specified (if allowed).
    /// @param governanceOpts The options used to initialize governance in the
    ///                       `Party` instance created if the crowdfund wins.
    /// @param hostIndex If the caller is a host, this is the index of the caller in the
    ///                  `governanceOpts.hosts` array. Only used if the
    ///                  crowdfund lost the current auction AND host are allowed
    ///                  to choose any next auction.
    /// @param nextNftTokenId The `tokenId` of the next NFT to bid on in the next
    ///                       auction. Only used if the crowdfund lost the
    ///                       current auction.
    /// @param nextAuctionId The `auctionId` of the the next auction. Only
    ///                      used if the crowdfund lost the current auction.
    /// @param nextMaximumBid The maximum bid the party can place for the next
    ///                       auction. Only used if the crowdfund lost the
    ///                       current auction.
    /// @param proof The Merkle proof used to verify that `nextAuctionId` and
    ///              `nextNftTokenId` are allowed. Only used if the crowdfund
    ///              lost the current auction.
    /// @return party_ Address of the `Party` instance created if successful.
    function finalizeOrRollOver(
        uint256 nextNftTokenId,
        uint256 nextAuctionId,
        uint96 nextMaximumBid,
        bytes32[] memory proof,
        FixedGovernanceOpts memory governanceOpts,
        uint256 hostIndex
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
            party_ = _createParty(governanceOpts, false, nftContract, nftTokenId);
            emit Won(lastBid, party_);

            _bidStatus = AuctionCrowdfundStatus.Finalized;
        } else if (lc == CrowdfundLifecycle.Expired) {
            // Crowdfund expired without NFT; finalize a loss.

            // Clear `lastBid` so `_getFinalPrice()` is 0 and people can redeem their
            // full contributions when they burn their participation NFTs.
            lastBid = 0;
            emit Lost();

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
                        proof,
                        allowedAuctionsMerkleRoot,
                        // Hash leaf with extra (empty) 32 bytes to prevent a second
                        // preimage attack by hashing >64 bytes.
                        keccak256(abi.encodePacked(bytes32(0), nextAuctionId, nextNftTokenId))
                    )
                ) {
                    revert BadNextAuctionError();
                }
            } else {
                // Let the host change to any next auction.
                _assertIsHost(msg.sender, governanceOpts, hostIndex);
            }

            // Check that the new auction can be bid on and is valid.
            _validateAuction(market, nextAuctionId, nftContract, nextNftTokenId);

            // Check that the next maximum bid is greater than the auction's minimum bid.
            uint256 minimumBid = market.getMinimumBid(nextAuctionId);
            if (nextMaximumBid < minimumBid) {
                revert MinimumBidExceedsMaximumBidError(minimumBid, nextMaximumBid);
            }

            // Update state for next auction.
            nftTokenId = nextNftTokenId;
            auctionId = nextAuctionId;
            maximumBid = nextMaximumBid;
            lastBid = 0;

            emit AuctionUpdated(nextNftTokenId, nextAuctionId, nextMaximumBid);

            // Change back the auction status from `Busy` to `Active`.
            _bidStatus = AuctionCrowdfundStatus.Active;
        }
    }
}
