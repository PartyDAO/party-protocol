// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../tokens/IERC721.sol";
import "../party/Party.sol";
import "../utils/Implementation.sol";
import "../utils/LibSafeERC721.sol";
import "../utils/LibRawResult.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "./IMarketWrapper.sol";
import "./PartyCrowdfund.sol";

contract PartyBid is Implementation, PartyCrowdfund {
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;
    using LibRawResult for bytes;

    enum FinalizeState {
        None,
        Finalizing,
        Finalized
    }

    struct PartyBidOptions {
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
        uint128 maximumBid;
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

    event Bid(uint256 bidAmount);
    event Won(uint256 bid, Party party);
    event Lost();

    error InvalidAuctionIdError();
    error AuctionFinalizedError(uint256 auctionId);
    error AlreadyHighestBidderError();
    error ExceedsMaximumBidError(uint256 bidAmount, uint256 maximumBid);
    error NoContributionsError();

    IERC721 public nftContract;
    uint256 public nftTokenId;
    uint256 public auctionId;
    uint128 public lastBid;
    uint128 public maximumBid;
    IMarketWrapper public market;
    uint40 public expiry;
    FinalizeState private _finalizeState;

    constructor(IGlobals globals) PartyCrowdfund(globals) {}

    function initialize(PartyBidOptions memory opts)
        external
        onlyDelegateCall
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
        nftContract = opts.nftContract;
        nftTokenId = opts.nftTokenId;
        market = opts.market;
        expiry = uint40(opts.duration + block.timestamp);
        auctionId = opts.auctionId;
        maximumBid = opts.maximumBid;

        if (!market.auctionIdMatchesToken(
            opts.auctionId,
            address(opts.nftContract),
            opts.nftTokenId))
        {
            revert InvalidAuctionIdError();
        }
    }

    function bid() external {
        {
            CrowdfundLifecycle lc = getCrowdfundLifecycle();
            if (lc != CrowdfundLifecycle.Active) {
                revert WrongLifecycleError(lc);
            }
        }
        uint256 auctionId_ = auctionId;
        if (market.isFinalized(auctionId_)) {
            revert AuctionFinalizedError(auctionId_);
        }
        if (market.getCurrentHighestBidder(auctionId_) == address(this)) {
            revert AlreadyHighestBidderError();
        }
        uint128 bidAmount = market.getMinimumBid(auctionId_).safeCastUint256ToUint128();
        if (bidAmount > maximumBid) {
            revert ExceedsMaximumBidError(bidAmount, maximumBid);
        }
        lastBid = bidAmount;
        (bool s, bytes memory r) = address(market).delegatecall(abi.encodeCall(
            IMarketWrapper.bid,
            (auctionId_, bidAmount)
        ));
        if (!s) {
            r.rawRevert();
        }
        emit Bid(bidAmount);
    }

    // Claim NFT and create a party if won or rescind bid if lost/expired.
    function finalize(FixedGovernanceOpts memory governanceOpts)
        external
        returns (Party party_)
    {
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc != CrowdfundLifecycle.Active && lc != CrowdfundLifecycle.Expired) {
            revert WrongLifecycleError(lc);
        }
        // Mark as finalizing to prevent burn(), bid(), and contribute()
        // getting called.
        _finalizeState = FinalizeState.Finalizing;
        uint128 lastBid_ = lastBid;
        // Only finalize on the market if we placed a bid.
        if (lastBid_ != 0) {
            // Can reenter and call burn() because _wasFinalized && party == 0 -> Lost
            (bool s, bytes memory r) = address(market).call(abi.encodeCall(
                IMarketWrapper.finalize,
                auctionId
            ));
            if (!s) {
                r.rawRevert();
            }
        }
        if (nftContract.safeOwnerOf(nftTokenId) == address(this)) {
            if (lastBid_ == 0) {
                // The NFT was gifted to us. Everyone wins.
                lastBid_ = totalContributions;
                if (lastBid_ == 0) {
                    revert NoContributionsError();
                }
                lastBid = lastBid_;
            }
            party_ = _createParty(governanceOpts, nftContract, nftTokenId);
            emit Won(lastBid_, party_);
        } else {
            emit Lost();
        }
        _finalizeState = FinalizeState.Finalized;
    }

    function getCrowdfundLifecycle() public override view returns (CrowdfundLifecycle) {
        // Do not rely on `market.isFinalized()` in case `auctionId` gets reused.
        FinalizeState finalizeState_ = _finalizeState;
        if (finalizeState_ == FinalizeState.Finalized) {
            return address(party) != address(0)
                // If we're fully finalized and we have a party instance then we won.
                ? CrowdfundLifecycle.Won
                // Otherwise we lost.
                : CrowdfundLifecycle.Lost;
        }
        if (finalizeState_ == FinalizeState.Finalizing) {
            // In the midst of finalizing (trying to reenter).
            return CrowdfundLifecycle.Busy;
        }
        if (block.timestamp >= expiry) {
            // Expired. finalize() needs to be called.
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
