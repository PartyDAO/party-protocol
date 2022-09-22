// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity ^0.8;

import "../tokens/IERC721.sol";
import "../party/Party.sol";
import "../utils/Implementation.sol";
import "../utils/LibSafeERC721.sol";
import "../utils/LibRawResult.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "../market-wrapper/IMarketWrapper.sol";
import "./Crowdfund.sol";

/// @notice A crowdfund that can repeatedly bid on an auction for a specific NFT
///         (i.e. with a known token ID) until it wins.
contract AuctionCrowdfund is Crowdfund {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;
    using LibRawResult for bytes;

    enum AuctionCrowdfundStatus {
        // The crowdfund has been created and contributions can be made and
        // acquisition functions may be called.
        Active,
        // An temporary state set by the contract during complex operations to
        // act as a reentrancy guard.
        Busy,
        // The crowdfund is over and has either won or lost.
        Finalized
    }

    struct AuctionCrowdfundOptions {
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
        // Fixed governance options (i.e. cannot be changed) that the governance
        // `Party` will be created with if the crowdfund succeeds.
        FixedGovernanceOpts governanceOpts;
    }

    event Bid(uint256 bidAmount);
    event Won(uint256 bid, Party party);
    event Lost();

    error InvalidAuctionIdError();
    error AuctionFinalizedError(uint256 auctionId);
    error AlreadyHighestBidderError();
    error ExceedsMaximumBidError(uint256 bidAmount, uint256 maximumBid);
    error NoContributionsError();
    error AuctionNotExpiredError();

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
    // Track extra status of the crowdfund specific to bids.
    AuctionCrowdfundStatus private _bidStatus;

    // Set the `Globals` contract.
    constructor(IGlobals globals) Crowdfund(globals) {}

    /// @notice Initializer to be delegatecalled by `Proxy` constructor. Will
    ///         revert if called outside the constructor.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    function initialize(AuctionCrowdfundOptions memory opts)
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
        if (!market.auctionIdMatchesToken(
            opts.auctionId,
            address(opts.nftContract),
            opts.nftTokenId))
        {
            revert InvalidAuctionIdError();
        }
    }

    /// @notice Accept naked ETH, e.g., if an auction needs to return ETH to us.
    receive() external payable {}

    /// @notice Place a bid on the NFT using the funds in this crowdfund,
    ///         placing the minimum possible bid to be the highest bidder, up to
    ///         `maximumBid`.
    function bid() external onlyDelegateCall {
        // Check that the auction is still active.
        {
            CrowdfundLifecycle lc = getCrowdfundLifecycle();
            if (lc != CrowdfundLifecycle.Active) {
                revert WrongLifecycleError(lc);
            }
        }
        // Mark as busy to prevent `burn()`, `bid()`, and `contribute()`
        // getting called because this will result in a `CrowdfundLifecycle.Busy`.
        _bidStatus = AuctionCrowdfundStatus.Busy;
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

        _bidStatus = AuctionCrowdfundStatus.Active;
    }

    /// @notice Calls finalize() on the market adapter, which will claim the NFT
    ///         (if necessary) if we won, or recover our bid (if necessary)
    ///         if we lost. If we won, a governance party will also be created.
    /// @param governanceOpts The options used to initialize governance in the
    ///                       `Party` instance created if the crowdfund wins.
    /// @return party_ Address of the `Party` instance created if successful.
    function finalize(FixedGovernanceOpts memory governanceOpts)
        external
        onlyDelegateCall
        returns (Party party_)
    {
        // Check that the auction is still active and has not passed the `expiry` time.
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc != CrowdfundLifecycle.Active && lc != CrowdfundLifecycle.Expired) {
            revert WrongLifecycleError(lc);
        }
        // Mark as busy to prevent burn(), bid(), and contribute()
        // getting called because this will result in a `CrowdfundLifecycle.Busy`.
        _bidStatus = AuctionCrowdfundStatus.Busy;

        uint96 lastBid_ = lastBid;
        // Only finalize on the market if we placed a bid.
        if (lastBid_ != 0) {
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
        } else {
            // If we never placed a bid, the auction must have expired.
            if (lc != CrowdfundLifecycle.Expired) {
                revert AuctionNotExpiredError();
            }
        }
        // Are we now in possession of the NFT?
        if (nftContract.safeOwnerOf(nftTokenId) == address(this)) {
            if (lastBid_ == 0) {
                // The NFT was gifted to us. Everyone who contributed wins.
                lastBid_ = totalContributions;
                if (lastBid_ == 0) {
                    // Nobody ever contributed. The NFT is effectively burned.
                    revert NoContributionsError();
                }
                lastBid = lastBid_;
            }
            // Create a governance party around the NFT.
            party_ = _createParty(
                _getPartyFactory(),
                governanceOpts,
                nftContract,
                nftTokenId
            );
            emit Won(lastBid_, party_);
        } else {
            // Clear `lastBid` so `_getFinalPrice()` is 0 and people can redeem their
            // full contributions when they burn their participation NFTs.
            lastBid = 0;
            emit Lost();
        }

        _bidStatus = AuctionCrowdfundStatus.Finalized;
    }

    /// @inheritdoc Crowdfund
    function getCrowdfundLifecycle() public override view returns (CrowdfundLifecycle) {
        // Do not rely on `market.isFinalized()` in case `auctionId` gets reused.
        AuctionCrowdfundStatus status = _bidStatus;
        if (status == AuctionCrowdfundStatus.Busy) {
            // In the midst of finalizing/bidding (trying to reenter).
            return CrowdfundLifecycle.Busy;
        }
        if (status == AuctionCrowdfundStatus.Finalized) {
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
}
