// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.17;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC721.sol";
import "../utils/LibSafeCast.sol";

import "./vendor/IOpenseaExchange.sol";
import "./vendor/IOpenseaConduitController.sol";
import "./ZoraHelpers.sol";
import "./LibProposal.sol";
import "./IProposalExecutionEngine.sol";

// Implements proposal listing an NFT on OpenSea (Seaport). Inherited by the `ProposalExecutionEngine`.
// This contract will be delegatecall'ed into by `Party` proxy instances.
abstract contract ListOnOpenseaProposal is ZoraHelpers {
    using LibSafeCast for uint256;

    enum ListOnOpenseaStep {
        // The proposal hasn't been executed yet.
        None,
        // The NFT was placed in a Zora auction.
        ListedOnZora,
        // The Zora auction was either skipped or cancelled.
        RetrievedFromZora,
        // The NFT was listed on OpenSea.
        ListedOnOpenSea
    }

    // ABI-encoded `proposalData` passed into execute.
    struct OpenseaProposalData {
        // The price (in ETH) to sell the NFT.
        uint256 listPrice;
        // How long the listing is valid for.
        uint40 duration;
        // The NFT token contract.
        IERC721 token;
        // the NFT token ID.
        uint256 tokenId;
        // Fees the taker must pay when filling the listing.
        uint256[] fees;
        // Respective recipients for each fee.
        address payable[] feeRecipients;
        // The first 4 bytes of the hash of a domain to attribute the listing to.
        // https://opensea.notion.site/opensea/Proposal-for-Seaport-Order-Attributions-via-Arbitrary-Domain-Hash-d0ad30b994ba48278c6e922983175285
        bytes4 domainHashPrefix;
    }

    // ABI-encoded `progressData` passed into execute in the `ListedOnOpenSea` step.
    struct OpenseaProgressData {
        // Hash of the OS order that was listed.
        bytes32 orderHash;
        // Expiration timestamp of the listing.
        uint40 expiry;
    }

    error OpenseaOrderStillActiveError(
        bytes32 orderHash,
        IERC721 token,
        uint256 tokenId,
        uint256 expiry
    );
    error InvalidFeeRecipients();

    event OpenseaOrderListed(
        IOpenseaExchange.OrderParameters orderParams,
        bytes32 orderHash,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint256 expiry
    );
    event OpenseaOrderSold(
        bytes32 orderHash,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice
    );
    event OpenseaOrderExpired(
        bytes32 orderHash,
        IERC721 token,
        uint256 tokenId,
        uint256 expiry
    );

    /// @notice The Seaport contract.
    IOpenseaExchange public immutable SEAPORT;
    /// @notice The Seaport conduit controller.
    IOpenseaConduitController public immutable CONDUIT_CONTROLLER;
    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    // Set immutables.
    constructor(
        IGlobals globals,
        IOpenseaExchange seaport,
        IOpenseaConduitController conduitController
    )
    {
        SEAPORT = seaport;
        CONDUIT_CONTROLLER = conduitController;
        _GLOBALS = globals;
    }

    // Try to create a listing (ultimately) on OpenSea (Seaport).
    // Creates a listing on Zora auction house for list price first. When that ends,
    // calling this function again will list on OpenSea. When that ends,
    // calling this function again will cancel the listing.
    function _executeListOnOpensea(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    )
        internal
        returns (bytes memory nextProgressData)
    {
        (OpenseaProposalData memory data) =
            abi.decode(params.proposalData, (OpenseaProposalData));
        bool isUnanimous = params.flags & LibProposal.PROPOSAL_FLAG_UNANIMOUS
            == LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        // If there is no `progressData` passed in, we're on the first step,
        // otherwise parse the first word of the `progressData` as the current step.
        ListOnOpenseaStep step = params.progressData.length == 0
            ? ListOnOpenseaStep.None
            : abi.decode(params.progressData, (ListOnOpenseaStep));
        if (step == ListOnOpenseaStep.None) {
            // First time executing the proposal.
            if (
                !isUnanimous &&
                LibProposal.isTokenIdPrecious(
                    data.token,
                    data.tokenId,
                    params.preciousTokens,
                    params.preciousTokenIds
                )
            ) {
                // Not a unanimous vote and the token is precious, so list on Zora
                // auction house first.
                uint40 zoraTimeout =
                    uint40(_GLOBALS.getUint256(LibGlobals.GLOBAL_OS_ZORA_AUCTION_TIMEOUT));
                uint40 zoraDuration =
                    uint40(_GLOBALS.getUint256(LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION));
                if (zoraTimeout != 0) {
                    uint256 auctionId = _createZoraAuction(
                        data.listPrice,
                        zoraTimeout,
                        zoraDuration,
                        data.token,
                        data.tokenId
                    );
                    // Return the next step and data required to execute that step.
                    return abi.encode(ListOnOpenseaStep.ListedOnZora, ZoraProgressData({
                        auctionId: auctionId,
                        minExpiry: (block.timestamp + zoraTimeout).safeCastUint256ToUint40()
                    }));
                }
            }
            // Unanimous vote, not a precious, or no Zora duration.
            // Advance past the Zora auction phase by pretending we already
            // retrieved it from Zora.
            step = ListOnOpenseaStep.RetrievedFromZora;
        }
        if (step == ListOnOpenseaStep.ListedOnZora) {
            // The last time this proposal was executed, we listed it on Zora.
            // Now retrieve it from Zora.
            (, ZoraProgressData memory zpd) =
                abi.decode(params.progressData, (uint8, ZoraProgressData));
            // Try to settle the Zora auction. This will revert if the auction
            // is still ongoing.
            ZoraAuctionStatus statusCode = _settleZoraAuction(
                zpd.auctionId,
                zpd.minExpiry,
                data.token,
                data.tokenId
            );
            if (
                statusCode == ZoraAuctionStatus.Sold ||
                statusCode == ZoraAuctionStatus.Cancelled
            ) {
                // Auction sold or was cancelled. If it sold, there is nothing left to do.
                // If it was cancelled, we cannot safely proceed with the listing. Return
                // empty progress data to indicate there are no more steps to
                // execute.
                return "";
            }
            // The auction simply expired before anyone bid on it. We have the NFT
            // back now so move on to listing it on OpenSea immediately.
            step = ListOnOpenseaStep.RetrievedFromZora;
        }
        if (step == ListOnOpenseaStep.RetrievedFromZora) {
            // This step occurs if either:
            // 1) This is the first time this proposal is being executed and
            //    it is a unanimous vote or the NFT is not precious (guarded)
            //    so we intentionally skip the Zora listing step.
            // 2) The last time this proposal was executed, we settled an expired
            //    (no bids) Zora auction and can now proceed to the OpenSea
            //    listing step.

            {
                // Clamp the order duration to the global minimum and maximum.
                uint40 minDuration = uint40(_GLOBALS.getUint256(LibGlobals.GLOBAL_OS_MIN_ORDER_DURATION));
                uint40 maxDuration = uint40(_GLOBALS.getUint256(LibGlobals.GLOBAL_OS_MAX_ORDER_DURATION));
                if (minDuration != 0 && data.duration < minDuration) {
                    data.duration = minDuration;
                } else if (maxDuration != 0 && data.duration > maxDuration) {
                    data.duration = maxDuration;
                }
            }
            uint256 expiry = block.timestamp + uint256(data.duration);
            bytes32 orderHash = _listOnOpensea(
                data.token,
                data.tokenId,
                data.listPrice,
                expiry,
                data.fees,
                data.feeRecipients,
                data.domainHashPrefix
            );
            return abi.encode(ListOnOpenseaStep.ListedOnOpenSea, orderHash, expiry);
        }
        assert(step == ListOnOpenseaStep.ListedOnOpenSea);
        // The last time this proposal was executed, we listed it on OpenSea.
        // Now try to settle the listing (either it has expired or been filled).
        (, OpenseaProgressData memory opd) =
            abi.decode(params.progressData, (uint8, OpenseaProgressData));
        _cleanUpListing(
            opd.orderHash,
            opd.expiry,
            data.token,
            data.tokenId,
            data.listPrice
        );
        // This is the last possible step so return empty progress data
        // to indicate there are no more steps to execute.
        return "";
    }

    function _listOnOpensea(
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint256 expiry,
        uint256[] memory fees,
        address payable[] memory feeRecipients,
        bytes4 domainHashPrefix
    )
        private
        returns (bytes32 orderHash)
    {
        if (fees.length != feeRecipients.length) {
            revert InvalidFeeRecipients();
        }
        // Approve OpenSea's conduit to spend our NFT. This should revert if we
        // do not own the NFT.
        bytes32 conduitKey = _GLOBALS.getBytes32(LibGlobals.GLOBAL_OPENSEA_CONDUIT_KEY);
        (address conduit,) = CONDUIT_CONTROLLER.getConduit(conduitKey);
        token.approve(conduit, tokenId);

        // Create a (basic) Seaport 721 sell order.
        IOpenseaExchange.Order[] memory orders = new IOpenseaExchange.Order[](1);
        IOpenseaExchange.Order memory order = orders[0];
        IOpenseaExchange.OrderParameters memory orderParams = order.parameters;
        orderParams.offerer = address(this);
        orderParams.startTime = block.timestamp;
        orderParams.endTime = expiry;
        orderParams.zone = _GLOBALS.getAddress(LibGlobals.GLOBAL_OPENSEA_ZONE);
        orderParams.orderType = orderParams.zone == address(0)
            ? IOpenseaExchange.OrderType.FULL_OPEN
            : IOpenseaExchange.OrderType.FULL_RESTRICTED;
        orderParams.salt = uint256(bytes32(domainHashPrefix));
        orderParams.conduitKey = conduitKey;
        orderParams.totalOriginalConsiderationItems = 1 + fees.length;
        // What we are selling.
        orderParams.offer = new IOpenseaExchange.OfferItem[](1);
        {
            IOpenseaExchange.OfferItem memory offer = orderParams.offer[0];
            offer.itemType = IOpenseaExchange.ItemType.ERC721;
            offer.token = address(token);
            offer.identifierOrCriteria = tokenId;
            offer.startAmount = 1;
            offer.endAmount = 1;
        }
        // What we want for it.
        orderParams.consideration = new IOpenseaExchange.ConsiderationItem[](1 + fees.length);
        {
            IOpenseaExchange.ConsiderationItem memory cons = orderParams.consideration[0];
            cons.itemType = IOpenseaExchange.ItemType.NATIVE;
            cons.token = address(0);
            cons.identifierOrCriteria = 0;
            cons.startAmount = cons.endAmount = listPrice;
            cons.recipient = payable(address(this));
            for (uint256 i; i < fees.length; ++i) {
                cons = orderParams.consideration[1 + i];
                cons.itemType = IOpenseaExchange.ItemType.NATIVE;
                cons.token = address(0);
                cons.identifierOrCriteria = 0;
                cons.startAmount = cons.endAmount = fees[i];
                cons.recipient = feeRecipients[i];
            }
        }
        orderHash = _getOrderHash(orderParams);
        // Validate the order on-chain so no signature is required to fill it.
        assert(SEAPORT.validate(orders));
        emit OpenseaOrderListed(
            orderParams,
            orderHash,
            token,
            tokenId,
            listPrice,
            expiry
        );
    }

    function _getOrderHash(IOpenseaExchange.OrderParameters memory orderParams)
        private
        view
        returns (bytes32 orderHash)
    {
        // `getOrderHash()` wants an `OrderComponents` struct, which is an `OrderParameters`
        // struct but with the last field (`totalOriginalConsiderationItems`)
        // replaced with the maker's nonce. Since we (the maker) never increment
        // our Seaport nonce, it is always 0.
        // So we temporarily set the `totalOriginalConsiderationItems` field to 0,
        // force cast the `OrderParameters` into a `OrderComponents` type, call
        // `getOrderHash()`, and then restore the `totalOriginalConsiderationItems`
        // field's value before returning.
        uint256 origTotalOriginalConsiderationItems =
            orderParams.totalOriginalConsiderationItems;
        orderParams.totalOriginalConsiderationItems = 0;
        IOpenseaExchange.OrderComponents memory orderComps;
        assembly { orderComps := orderParams }
        orderHash = SEAPORT.getOrderHash(orderComps);
        orderParams.totalOriginalConsiderationItems = origTotalOriginalConsiderationItems;
    }

    function _cleanUpListing(
        bytes32 orderHash,
        uint256 expiry,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice
    )
        private
    {
        (,, uint256 totalFilled,) = SEAPORT.getOrderStatus(orderHash);
        if (totalFilled != 0) {
            // The order was filled before it expired. We no longer have the NFT
            // and instead we have the ETH it was bought with.
            emit OpenseaOrderSold(orderHash, token, tokenId, listPrice);
        } else if (expiry <= block.timestamp) {
            // The order expired before it was filled. We retain the NFT.
            // Revoke Seaport approval.
            token.approve(address(0), tokenId);
            emit OpenseaOrderExpired(orderHash, token, tokenId, expiry);
        } else {
            // The order hasn't been bought and is still active.
            revert OpenseaOrderStillActiveError(orderHash, token, tokenId, expiry);
        }
    }
}
