// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.17;

import "openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "../tokens/IERC721.sol";
import "../party/Party.sol";
import "../utils/Implementation.sol";
import "../utils/LibSafeERC721.sol";
import "../utils/LibRawResult.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "../market-wrapper/IMarketWrapper.sol";
import "./Crowdfund.sol";

/// @notice A crowdfund that can repeatedly bid on auctions for an NFT from a
///         specific collection on a specific market (eg. Nouns) and can
///         continue bidding on new auctions until it wins.
contract RollingAuctionCrowdfund is Implementation, Crowdfund {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;
    using LibRawResult for bytes;

    enum RollingAuctionCrowdfundStatus {
        // The crowdfund has been created and contributions can be made and
        // acquisition functions may be called.
        Active,
        // An temporary state set by the contract during complex operations to
        // act as a reentrancy guard.
        Busy,
        // The crowdfund is over and has either won or lost.
        Finalized
    }

    struct RollingAuctionCrowdfundOptions {
        // The name of the crowdfund.
        // This will also carry over to the governance party.
        string name;
        // The token symbol for both the crowdfund and the governance NFTs.
        string symbol;
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
        // Maximum bid allowed.
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

    event Bid(uint256 bidAmount);
    event Won(uint256 bid, Party party);
    event AuctionUpdated(uint256 nextNftTokenId, uint256 nextAuctionId);
    event Lost();

    error InvalidAuctionIdError();
    error AuctionFinalizedError(uint256 auctionId);
    error AlreadyHighestBidderError();
    error ExceedsMaximumBidError(uint256 bidAmount, uint256 maximumBid);
    error NoContributionsError();
    error AuctionNotExpiredError();
    error BadNextAuctionError();

    /// @notice The NFT contract to buy.
    IERC721 public nftContract;
    /// @notice The NFT token ID to buy.
    uint256 public nftTokenId;
    /// @notice An adapter for the auction market (Zora, OpenSea, etc).
    /// @dev This will be delegatecalled into to execute bids.
    IMarketWrapper public market;
    /// @notice The auction ID to identify the auction on the `market`.
    uint256 public auctionId;
    /// @notice The maximum possible bid this crowdfund can make.
    uint96 public maximumBid;
    /// @notice The last successful bid() amount.
    uint96 public lastBid;
    /// @notice When this crowdfund expires. If the NFT has not been bought
    ///         by this time, participants can withdraw their contributions.
    uint40 public expiry;
    /// @notice Whether the party is only allowing a host to call `bid()`.
    bool public onlyHostCanBid;
    // Track extra status of the crowdfund specific to bids.
    RollingAuctionCrowdfundStatus private _bidStatus;
    /// @notice Merkle root of list of allowed next auctions that can be rolled
    ///         over to if the current auction loses. Each leaf should be hashed
    ///         as `keccak256(abi.encodePacked(auctionId, tokenId)))` where
    ///         `auctionId` is the auction ID of the auction to allow and
    ///         `tokenId` is the `tokenId` of the NFT being auctioned.
    bytes32 public allowedAuctionsMerkleRoot;

    // Set the `Globals` contract.
    constructor(IGlobals globals) Crowdfund(globals) {}

    /// @notice Initializer to be delegatecalled by `Proxy` constructor. Will
    ///         revert if called outside the constructor.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    function initialize(RollingAuctionCrowdfundOptions memory opts)
        external
        payable
        onlyConstructor
    {
        nftContract = opts.nftContract;
        nftTokenId = opts.nftTokenId;
        market = opts.market;
        expiry = uint40(opts.duration + block.timestamp);
        auctionId = opts.auctionId;
        maximumBid = opts.maximumBid;
        allowedAuctionsMerkleRoot = opts.allowedAuctionsMerkleRoot;
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

        // Check that the auction can be bid on and is valid.
        _validateAuction(
            opts.market,
            opts.auctionId,
            opts.nftContract,
            opts.nftTokenId
        );
    }

    /// @notice Accept naked ETH, e.g., if an auction needs to return ETH to us.
    receive() external payable {}

    /// @notice Place a bid on the NFT using the funds in this crowdfund,
    ///         placing the minimum possible bid to be the highest bidder, up to
    ///         `maximumBid`.
    /// @param governanceOpts The governance options the crowdfund was created with.
    /// @param hostIndex If the caller is a host, this is the index of the caller in the
    ///                  `governanceOpts.hosts` array.
    function bid(FixedGovernanceOpts memory governanceOpts, uint256 hostIndex)
        external
        onlyDelegateCall
    {
        // This function can be optionally restricted in different ways.
        if (onlyHostCanBid) {
            if (address(gateKeeper) != address(0)) {
                // `onlyHostCanBid` is true and we are using a gatekeeper. Either
                // the host or a contributor can call this function.
                _assertIsHostOrContributor(msg.sender, governanceOpts, hostIndex);
            } else {
                // `onlyHostCanBid` is true and we are NOT using a gatekeeper.
                // Only a host can call this function.
                _assertIsHost(msg.sender, governanceOpts, hostIndex);
            }
        } else if (address(gateKeeper) != address(0)) {
            // `onlyHostCanBid` is false and we are using a gatekeeper.
            // Only a contributor can call this function.
            _assertIsContributor(msg.sender);
        }

        // Check that the auction is still active.
        {
            CrowdfundLifecycle lc = getCrowdfundLifecycle();
            if (lc != CrowdfundLifecycle.Active) {
                revert WrongLifecycleError(lc);
            }
        }

        // Mark as busy to prevent `burn()`, `bid()`, and `contribute()`
        // getting called because this will result in a `CrowdfundLifecycle.Busy`.
        _bidStatus = RollingAuctionCrowdfundStatus.Busy;

        // Make sure the auction is not finalized.
        uint256 auctionId_ = auctionId;
        if (market.isFinalized(auctionId_)) {
            revert AuctionFinalizedError(auctionId_);
        }

        // Only bid if we are not already the highest bidder.
        if (market.getCurrentHighestBidder(auctionId_) == address(this)) {
            revert AlreadyHighestBidderError();
        }

        // Get the minimum necessary bid to be the highest bidder.
        uint96 bidAmount = market.getMinimumBid(auctionId_).safeCastUint256ToUint96();
        // Prevent unaccounted ETH from being used to inflate the bid and
        // create "ghost shares" in voting power.
        uint96 totalContributions_ = totalContributions;
        if (bidAmount > totalContributions_) {
            revert ExceedsTotalContributionsError(bidAmount, totalContributions_);
        }
        // Make sure the bid is less than the maximum bid.
        if (bidAmount > maximumBid) {
            revert ExceedsMaximumBidError(bidAmount, maximumBid);
        }
        lastBid = bidAmount;

        // No need to check that we have `bidAmount` since this will attempt to
        // transfer `bidAmount` ETH to the auction platform.
        (bool s, bytes memory r) = address(market).delegatecall(abi.encodeCall(
            IMarketWrapper.bid,
            (auctionId_, bidAmount)
        ));
        if (!s) {
            r.rawRevert();
        }
        emit Bid(bidAmount);

        _bidStatus = RollingAuctionCrowdfundStatus.Active;
    }

    /// @notice Calls `finalize()` on the market adapter, which will claim the NFT
    ///         (if necessary) if we won, or recover our bid (if necessary)
    ///         if the crowfund expired and we lost. If we lost but the
    ///         crowdfund has not expired, this will revert. Only call this to
    ///         finalize the result of a won or expired crowdfund, otherwise
    ///         call `finalizeOrRollOver()`.
    /// @param governanceOpts The options used to initialize governance in the
    ///                       `Party` instance created if the crowdfund wins.
    /// @return party_ Address of the `Party` instance created if successful.
    function finalize(FixedGovernanceOpts memory governanceOpts)
        external
        onlyDelegateCall
        returns (Party party_)
    {
        // If the crowdfund won, only `governanceOpts` is relevant. The rest are ignored.
        return finalizeOrRollOver(governanceOpts, 0, 0, 0, new bytes32[](0));
    }

    /// @notice Calls `finalize()` on the market adapter, which will claim the NFT
    ///         (if necessary) if we won, or recover our bid (if necessary)
    ///         if the crowfund expired and we lost. If we lost but the
    ///         crowdfund has not expired, it will move on to the next auction
    ///         specified (if allowed).
    /// @param governanceOpts The options used to initialize governance in the
    ///                       `Party` instance created if the crowdfund wins.
    /// @param hostIndex If the caller is a host, this is the index of the caller in the
    ///                  `governanceOpts.hosts` array. Only used if the crowdfund loses.
    /// @param nextNftTokenId The `tokenId` of the next NFT to bid on in the next
    ///                       auction. Only used if the crowdfund loses.
    /// @param nextAuctionId The `auctionId` of the the next auction. Only
    ///                      used if the crowdfund loses.
    /// @param proof The Merkle proof used to verify that `nextAuctionId` and
    ///              `nextNftTokenId` are allowed. Only used if the crowdfund loses.
    /// @return party_ Address of the `Party` instance created if successful.
    function finalizeOrRollOver(
        FixedGovernanceOpts memory governanceOpts,
        uint256 hostIndex,
        uint256 nextNftTokenId,
        uint256 nextAuctionId,
        bytes32[] memory proof
    )
        public
        onlyDelegateCall
        returns (Party party_)
    {
        // Check that the auction is still active and has not passed the `expiry` time.
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc != CrowdfundLifecycle.Active && lc != CrowdfundLifecycle.Expired) {
            revert WrongLifecycleError(lc);
        }
        // Mark as busy to prevent `burn()`, `bid()`, and `contribute()`
        // getting called because this will result in a `CrowdfundLifecycle.Busy`.
        _bidStatus = RollingAuctionCrowdfundStatus.Busy;

        uint256 auctionId_ = auctionId;
        // Finalize the auction if it isn't finalized.
        if (!market.isFinalized(auctionId_)) {
            // Note that even if this crowdfund has expired but the auction is still
            // ongoing, this call can fail and block finalization until the auction ends.
            (bool s, bytes memory r) = address(market).call(abi.encodeCall(
                IMarketWrapper.finalize,
                auctionId_
            ));
            if (!s) {
                r.rawRevert();
            }
        }
        if (
            // Are we now in possession of the NFT?
            nftContract.safeOwnerOf(nftTokenId) == address(this) &&
            // And it wasn't acquired for free or "gifted" to us?
            address(this).balance < totalContributions
        ) {
            // Create a governance party around the NFT.
            party_ = _createParty(
                governanceOpts,
                false,
                nftContract,
                nftTokenId
            );
            // Create a governance party around the NFT.
            emit Won(lastBid, party_);

            _bidStatus = RollingAuctionCrowdfundStatus.Finalized;
        } else if (lc == CrowdfundLifecycle.Expired) {
            // Crowdfund expired without NFT; finalize a loss.

            // Clear `lastBid` so `_getFinalPrice()` is 0 and people can redeem their
            // full contributions when they burn their participation NFTs.
            lastBid = 0;
            emit Lost();

            _bidStatus = RollingAuctionCrowdfundStatus.Finalized;
        } else {
            // Move on to the next auction if this one has been lost (or, in
            // rare cases, if the NFT was acquired for free and funds remain
            // unused).

            if (allowedAuctionsMerkleRoot != bytes32(0)) {
                // Check that the next `auctionId` and `tokenId` for the next
                // auction to roll over have been allowed.
                if (!MerkleProof.verify(
                    proof,
                    allowedAuctionsMerkleRoot,
                    // Hash leaf with extra (empty) 32 bytes to prevent a second
                    // preimage attack by hashing >64 bytes.
                    keccak256(abi.encodePacked(bytes32(0), nextAuctionId, nextNftTokenId))))
                {
                    revert BadNextAuctionError();
                }
            } else {
                // Let the host change to any next auction.
                _assertIsHost(msg.sender, governanceOpts, hostIndex);
            }

            // Check that the new auction can be bid on and is valid.
            _validateAuction(market, nextAuctionId, nftContract, nextNftTokenId);

            // Update state for next auction.
            nftTokenId = nextNftTokenId;
            auctionId = nextAuctionId;
            lastBid = 0;

            emit AuctionUpdated(nextNftTokenId, nextAuctionId);

            // Change back the auction status from `Busy` to `Active`.
            _bidStatus = RollingAuctionCrowdfundStatus.Active;
        }
    }

    /// @inheritdoc Crowdfund
    function getCrowdfundLifecycle() public override view returns (CrowdfundLifecycle) {
        // Do not rely on `market.isFinalized()` in case `auctionId` gets reused.
        RollingAuctionCrowdfundStatus status = _bidStatus;
        if (status == RollingAuctionCrowdfundStatus.Busy) {
            // In the midst of finalizing/bidding (trying to reenter).
            return CrowdfundLifecycle.Busy;
        }
        if (status == RollingAuctionCrowdfundStatus.Finalized) {
            return address(party) != address(0)
                // If we're fully finalized and we have a party instance then we won.
                ? CrowdfundLifecycle.Won
                // Otherwise we lost.
                : CrowdfundLifecycle.Lost;
        }
        if (block.timestamp >= expiry) {
            // Expired. `finalize()` needs to be called.
            return CrowdfundLifecycle.Expired;
        }
        return CrowdfundLifecycle.Active;
    }

    function _getFinalPrice()
        internal
        override
        view
        returns (uint256 price)
    {
        return lastBid;
    }

    function _validateAuction(
        IMarketWrapper market_,
        uint256 auctionId_,
        IERC721 nftContract_,
        uint256 nftTokenId_
    ) private view {
        if (!market_.auctionIdMatchesToken(
            auctionId_,
            address(nftContract_),
            nftTokenId_))
        {
            revert InvalidAuctionIdError();
        }
    }
}