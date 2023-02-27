// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../tokens/IERC721.sol";
import "../party/Party.sol";
import "../utils/Implementation.sol";
import "../utils/LibSafeERC721.sol";
import "../utils/LibRawResult.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "../market-wrapper/IMarketWrapper.sol";
import "./Crowdfund.sol";

abstract contract AuctionCrowdfundBase is Crowdfund {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;
    using LibRawResult for bytes;

    enum AuctionCrowdfundStatus {
        // The crowdfund has been created and contributions can be made and
        // acquisition functions may be called.
        Active,
        // A temporary state set by the contract during complex operations to
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
        // Minimum amount of ETH that can be contributed to this crowdfund per address.
        uint96 minContribution;
        // Maximum amount of ETH that can be contributed to this crowdfund per address.
        uint96 maxContribution;
        // The gatekeeper contract to use (if non-null) to restrict who can
        // contribute to this crowdfund. If used, only contributors or hosts can
        // call `bid()`.
        IGateKeeper gateKeeper;
        // The gate ID within the gateKeeper contract to use.
        bytes12 gateKeeperId;
        // Whether the party is only allowing a host to call `bid()`.
        bool onlyHostCanBid;
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
    error MinimumBidExceedsMaximumBidError(uint256 bidAmount, uint256 maximumBid);
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
    /// @notice Whether the party is only allowing a host to call `bid()`.
    bool public onlyHostCanBid;
    // Track extra status of the crowdfund specific to bids.
    AuctionCrowdfundStatus internal _bidStatus;

    // Set the `Globals` contract.
    constructor(IGlobals globals) Crowdfund(globals) {}

    /// @notice Initializer to be delegatecalled by `Proxy` constructor. Will
    ///         revert if called outside the constructor.
    /// @param opts Options used to initialize the crowdfund. These are fixed
    ///             and cannot be changed later.
    function _initialize(AuctionCrowdfundOptions memory opts) internal {
        if (opts.onlyHostCanBid && opts.governanceOpts.hosts.length == 0) {
            revert MissingHostsError();
        }
        nftContract = opts.nftContract;
        nftTokenId = opts.nftTokenId;
        market = opts.market;
        expiry = uint40(opts.duration + block.timestamp);
        auctionId = opts.auctionId;
        maximumBid = opts.maximumBid;
        onlyHostCanBid = opts.onlyHostCanBid;
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

        // Check that the auction can be bid on and is valid.
        _validateAuction(opts.market, opts.auctionId, opts.nftContract, opts.nftTokenId);

        // Check that the minimum bid is less than the maximum bid.
        uint256 minimumBid = opts.market.getMinimumBid(opts.auctionId);
        if (minimumBid > opts.maximumBid) {
            revert MinimumBidExceedsMaximumBidError(minimumBid, opts.maximumBid);
        }
    }

    /// @notice Accept naked ETH, e.g., if an auction needs to return ETH to us.
    receive() external payable {}

    /// @notice Place a bid on the NFT using the funds in this crowdfund,
    ///         placing the minimum possible bid to be the highest bidder, up to
    ///         `maximumBid`. Only callable by contributors if `onlyHostCanBid`
    ///         is not enabled.
    function bid() external {
        if (onlyHostCanBid) revert OnlyPartyHostError();

        // Bid with the minimum amount to be the highest bidder.
        _bid(type(uint96).max);
    }

    /// @notice Place a bid on the NFT using the funds in this crowdfund,
    ///         placing the minimum possible bid to be the highest bidder, up to
    ///         `maximumBid`.
    /// @param governanceOpts The governance options the crowdfund was created
    ///                       with. Only used for crowdfunds where only a host
    ///                       can bid to verify the caller is a host.
    /// @param hostIndex If the caller is a host, this is the index of the caller in the
    ///                  `governanceOpts.hosts` array. Only used for crowdfunds where only
    ///                  a host can bid to verify the caller is a host.
    function bid(FixedGovernanceOpts memory governanceOpts, uint256 hostIndex) external {
        // This function can be optionally restricted in different ways.
        if (onlyHostCanBid) {
            // Only a host can call this function.
            _assertIsHost(msg.sender, governanceOpts, hostIndex);
        } else if (address(gateKeeper) != address(0)) {
            // `onlyHostCanBid` is false and we are using a gatekeeper.
            // Only a contributor can call this function.
            _assertIsContributor(msg.sender);
        }

        // Bid with the minimum amount to be the highest bidder.
        _bid(type(uint96).max);
    }

    /// @notice Place a bid on the NFT using the funds in this crowdfund,
    ///         placing a bid, up to `maximumBid`. Only host can call this.
    /// @param amount The amount to bid.
    /// @param governanceOpts The governance options the crowdfund was created
    ///                       with. Used to verify the caller is a host.
    /// @param hostIndex If the caller is a host, this is the index of the caller in the
    ///                  `governanceOpts.hosts` array. Used to verify the caller is a host.
    function bid(
        uint96 amount,
        FixedGovernanceOpts memory governanceOpts,
        uint256 hostIndex
    ) external {
        // Only a host can specify a custom bid amount.
        _assertIsHost(msg.sender, governanceOpts, hostIndex);

        _bid(amount);
    }

    function _bid(uint96 amount) private onlyDelegateCall {
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
        IMarketWrapper market_ = market;
        uint256 auctionId_ = auctionId;
        if (market_.isFinalized(auctionId_)) {
            revert AuctionFinalizedError(auctionId_);
        }

        // Only bid if we are not already the highest bidder.
        if (market_.getCurrentHighestBidder(auctionId_) == address(this)) {
            revert AlreadyHighestBidderError();
        }

        if (amount == type(uint96).max) {
            // Get the minimum necessary bid to be the highest bidder.
            amount = market_.getMinimumBid(auctionId_).safeCastUint256ToUint96();
        }

        // Prevent unaccounted ETH from being used to inflate the bid and
        // create "ghost shares" in voting power.
        uint96 totalContributions_ = totalContributions;
        if (amount > totalContributions_) {
            revert ExceedsTotalContributionsError(amount, totalContributions_);
        }
        // Make sure the bid is less than the maximum bid.
        uint96 maximumBid_ = maximumBid;
        if (amount > maximumBid_) {
            revert ExceedsMaximumBidError(amount, maximumBid_);
        }
        lastBid = amount;

        // No need to check that we have `amount` since this will attempt to
        // transfer `amount` ETH to the auction platform.
        (bool s, bytes memory r) = address(market_).delegatecall(
            abi.encodeCall(IMarketWrapper.bid, (auctionId_, amount))
        );
        if (!s) {
            r.rawRevert();
        }
        emit Bid(amount);

        _bidStatus = AuctionCrowdfundStatus.Active;
    }

    /// @inheritdoc Crowdfund
    function getCrowdfundLifecycle() public view override returns (CrowdfundLifecycle) {
        // Do not rely on `market.isFinalized()` in case `auctionId` gets reused.
        AuctionCrowdfundStatus status = _bidStatus;
        if (status == AuctionCrowdfundStatus.Busy) {
            // In the midst of finalizing/bidding (trying to reenter).
            return CrowdfundLifecycle.Busy;
        }
        if (status == AuctionCrowdfundStatus.Finalized) {
            return
                address(party) != address(0) // If we're fully finalized and we have a party instance then we won.
                    ? CrowdfundLifecycle.Won // Otherwise we lost.
                    : CrowdfundLifecycle.Lost;
        }
        if (block.timestamp >= expiry) {
            // Expired. `finalize()` needs to be called.
            return CrowdfundLifecycle.Expired;
        }
        return CrowdfundLifecycle.Active;
    }

    function _getFinalPrice() internal view override returns (uint256 price) {
        return lastBid;
    }

    function _validateAuction(
        IMarketWrapper market_,
        uint256 auctionId_,
        IERC721 nftContract_,
        uint256 nftTokenId_
    ) internal view {
        if (!market_.auctionIdMatchesToken(auctionId_, address(nftContract_), nftTokenId_)) {
            revert InvalidAuctionIdError();
        }
    }

    function _finalizeAuction(
        CrowdfundLifecycle lc,
        IMarketWrapper market_,
        uint256 auctionId_,
        uint96 lastBid_
    ) internal {
        // Mark as busy to prevent `burn()`, `bid()`, and `contribute()`
        // getting called because this will result in a `CrowdfundLifecycle.Busy`.
        _bidStatus = AuctionCrowdfundStatus.Busy;

        // If we've bid before or the CF is not expired, finalize the auction.
        if (lastBid_ != 0 || lc == CrowdfundLifecycle.Active) {
            if (!market_.isFinalized(auctionId_)) {
                // If the crowdfund has expired and we are not the highest
                // bidder, skip finalization because there is no chance of
                // winning the auction.
                if (
                    lc == CrowdfundLifecycle.Expired &&
                    market_.getCurrentHighestBidder(auctionId_) != address(this)
                ) return;

                (bool s, bytes memory r) = address(market_).call(
                    abi.encodeCall(IMarketWrapper.finalize, auctionId_)
                );
                if (!s) {
                    r.rawRevert();
                }
            }
        }
    }
}
