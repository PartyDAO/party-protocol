// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC721.sol";

import "./opensea/ISeaportExchange.sol";
import "./opensea/ISeaportConduitController.sol";
import "./ZoraHelpers.sol";
import "./LibProposal.sol";
import "./IProposalExecutionEngine.sol";

// Implements propoasls listing an NFT on open sea.
abstract contract ListOnOpenSeaportProposal is ZoraHelpers {
    enum ListOnOpenSeaportStep {
        // The proposal hasn't been executed yet.
        None,
        // The NFT was placed in a zora auction.
        ListedOnZora,
        // The Zora auction was either skipped or cancelled.
        RetrievedFromZora,
        // The NFT was listed on OpenSea.
        ListedOnOpenSea
    }

    // ABI-encoded `proposalData` passed into execute.
    struct OpenSeaportProposalData {
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
    }

    // ABI-encoded `progressData` passed into execute in the `ListedOnOpenSea` step.
    struct OpenSeaportProgressData {
        // Hash of the OS order that was listed.
        bytes32 orderHash;
        // Expiration timestamp of the listing.
        uint40 expiry;
    }

    error OpenSeaportOrderStillActiveError(
        bytes32 orderHash,
        IERC721 token,
        uint256 tokenId,
        uint256 expiry
    );
    error InvalidFeeRecipients();

    event OpenSeaportOrderListed(
        ISeaportExchange.OrderParameters orderParams,
        bytes32 orderHash,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint256 expiry
    );
    event OpenSeaportOrderSold(
        bytes32 orderHash,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice
    );
    event OpenSeaportOrderExpired(
        bytes32 orderHash,
        IERC721 token,
        uint256 tokenId,
        uint256 expiry
    );
    // Coordinated event w/OS team to track on-chain orders.
    event OrderValidated(
        bytes32 orderHash,
        address indexed offerer,
        address indexed zone,
        ISeaportExchange.OfferItem[] offer,
        ISeaportExchange.ConsiderationItem[] consideration,
        ISeaportExchange.OrderType orderType,
        uint256 startTime,
        uint256 endTime,
        bytes32 zoneHash,
        uint256 salt,
        bytes32 conduitKey,
        uint256 counter
    );

    ISeaportExchange public immutable SEAPORT;
    ISeaportConduitController public immutable CONDUIT_CONTROLLER;
    IGlobals private immutable _GLOBALS;

    constructor(
        IGlobals globals,
        ISeaportExchange seaport,
        ISeaportConduitController conduitController
    )
    {
        SEAPORT = seaport;
        CONDUIT_CONTROLLER = conduitController;
        _GLOBALS =globals;
    }

    // Try to create a listing (ultimately) on OpenSea (Seaport).
    // Creates a listing on Zora AH for list price first. When that ends,
    // calling this function again will list in on OpenSea. When that ends,
    // calling this function again will cancel the listing.
    function _executeListOnOpenSeaport(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    )
        internal
        returns (bytes memory nextProgressData)
    {
        (OpenSeaportProposalData memory data) =
            abi.decode(params.proposalData, (OpenSeaportProposalData));
        bool isUnanimous = params.flags & LibProposal.PROPOSAL_FLAG_UNANIMOUS
            == LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        // If there is progressData passed in, we're on the first step,
        // otherwise parse the first word of the progressData as the current step.
        ListOnOpenSeaportStep step = params.progressData.length == 0
            ? ListOnOpenSeaportStep.None
            : abi.decode(params.progressData, (ListOnOpenSeaportStep));
        if (step == ListOnOpenSeaportStep.None) {
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
                // Not a unanimous vote and the token is precious, so list on zora
                // AH first.
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
                    return abi.encode(ListOnOpenSeaportStep.ListedOnZora, ZoraProgressData({
                        auctionId: auctionId,
                        minExpiry: uint40(block.timestamp + zoraTimeout)
                    }));
                }
            }
            // Unanimous vote, not a precious, or no zora duration.
            // Advance past the zora auction phase by pretending we already
            // retrieved it from zora.
            step = ListOnOpenSeaportStep.RetrievedFromZora;
        }
        if (step == ListOnOpenSeaportStep.ListedOnZora) {
            // The last time this proposal was executed, we listed it on zora.
            // Now retrieve it from zora.
            (, ZoraProgressData memory zpd) =
                abi.decode(params.progressData, (uint8, ZoraProgressData));
            // Try to settle the zora auction. This will revert if the auction
            // is still ongoing.
            if (_settleZoraAuction(zpd.auctionId, zpd.minExpiry, data.token, data.tokenId)) {
                // Auction sold. Nothing left to do. Return empty progress data
                // to indicate there are no more steps to execute.
                return "";
            }
            // The auction simply expired before anyone bid on it. We have the NFT
            // back now so move on to listing it on opensea immediately.
            step = ListOnOpenSeaportStep.RetrievedFromZora;
        }
        if (step == ListOnOpenSeaportStep.RetrievedFromZora) {
            // This step occurs if either:
            // 1) This is the first time this proposal is being executed and
            //    it is a unanimous vote or the NFT is not precious (guarded)
            //    so we intentionally skip the zora listing step.
            // 2) The last time this proposal was executed, we settled an expired
            //    (no bids) zora auction and can now proceed to the opensea
            //    listing step.
            uint256 expiry = block.timestamp + uint256(data.duration);
            bytes32 orderHash = _listOnOpenSeaport(
                data.token,
                data.tokenId,
                data.listPrice,
                expiry,
                data.fees,
                data.feeRecipients
            );
            return abi.encode(ListOnOpenSeaportStep.ListedOnOpenSea, orderHash, expiry);
        }
        assert(step == ListOnOpenSeaportStep.ListedOnOpenSea);
        // The last time this proposal was executed, we listed it on opensea.
        // Now try to settle the listing (either it has expired or been filled).
        (, OpenSeaportProgressData memory opd) =
            abi.decode(params.progressData, (uint8, OpenSeaportProgressData));
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

    function _listOnOpenSeaport(
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint256 expiry,
        uint256[] memory fees,
        address payable[] memory feeRecipients
    )
        private
        returns (bytes32 orderHash)
    {
        if (fees.length != feeRecipients.length) {
            revert InvalidFeeRecipients();
        }
        // Approve opensea's conduit to spend our NFT. This should revert if we do not own
        // the NFT.
        bytes32 conduitKey = _GLOBALS.getBytes32(LibGlobals.GLOBAL_OPENSEA_CONDUIT_KEY);
        (address conduit,) = CONDUIT_CONTROLLER.getConduit(conduitKey);
        token.approve(conduit, tokenId);

        // Create a (basic) seaport 721 sell order.
        ISeaportExchange.Order[] memory orders = new ISeaportExchange.Order[](1);
        ISeaportExchange.Order memory order = orders[0];
        ISeaportExchange.OrderParameters memory orderParams = order.parameters;
        orderParams.offerer = address(this);
        orderParams.startTime = block.timestamp;
        orderParams.endTime = expiry;
        orderParams.zone = _GLOBALS.getAddress(LibGlobals.GLOBAL_OPENSEA_ZONE);
        orderParams.orderType = orderParams.zone == address(0)
            ? ISeaportExchange.OrderType.FULL_OPEN
            : ISeaportExchange.OrderType.FULL_RESTRICTED;
        orderParams.salt = 0;
        orderParams.conduitKey = conduitKey;
        orderParams.totalOriginalConsiderationItems = 1 + fees.length;
        // What we are selling.
        orderParams.offer = new ISeaportExchange.OfferItem[](1);
        {
            ISeaportExchange.OfferItem memory offer = orderParams.offer[0];
            offer.itemType = ISeaportExchange.ItemType.ERC721;
            offer.token = address(token);
            offer.identifierOrCriteria = tokenId;
            offer.startAmount = 1;
            offer.endAmount = 1;
        }
        // What we want for it.
        orderParams.consideration = new ISeaportExchange.ConsiderationItem[](1 + fees.length);
        {
            ISeaportExchange.ConsiderationItem memory cons = orderParams.consideration[0];
            cons.itemType = ISeaportExchange.ItemType.NATIVE;
            cons.token = address(0);
            cons.identifierOrCriteria = 0;
            cons.startAmount = cons.endAmount = listPrice;
            cons.recipient = payable(address(this));
            for (uint256 i = 0; i < fees.length; ++i) {
                cons = orderParams.consideration[1 + i];
                cons.itemType = ISeaportExchange.ItemType.NATIVE;
                cons.token = address(0);
                cons.identifierOrCriteria = 0;
                cons.startAmount = cons.endAmount = fees[i];
                cons.recipient = feeRecipients[i];
            }
        }
        orderHash = _getOrderHash(orderParams);
        // Validate the order on-chain so no signature is required to fill it.
        assert(SEAPORT.validate(orders));
        // Emit the the coordinated OS event so their backend can detect this order.
        emit OrderValidated(
            orderHash,
            orderParams.offerer,
            orderParams.zone,
            orderParams.offer,
            orderParams.consideration,
            orderParams.orderType,
            orderParams.startTime,
            orderParams.endTime,
            orderParams.zoneHash,
            orderParams.salt,
            orderParams.conduitKey,
            0
        );
        emit OpenSeaportOrderListed(
            orderParams,
            orderHash,
            token,
            tokenId,
            listPrice,
            expiry
        );
    }

    function _getOrderHash(ISeaportExchange.OrderParameters memory orderParams)
        private
        view
        returns (bytes32 orderHash)
    {
        // getOrderHash() wants an OrderComponents struct, which is an OrderParameters
        // struct but with the last field (totalOriginalConsiderationItems)
        // replaced with the maker's nonce. Since we (the maker) never increment
        // our seaport nonce, it is always 0.
        // So we temporarily set the totalOriginalConsiderationItems field to 0,
        // force cast the OrderParameters into a OrderComponents type, call
        // getOrderHash(), and then restore the totalOriginalConsiderationItems
        // field's value before returning.
        uint256 origTotalOriginalConsiderationItems =
            orderParams.totalOriginalConsiderationItems;
        orderParams.totalOriginalConsiderationItems = 0;
        ISeaportExchange.OrderComponents memory orderComps;
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
            emit OpenSeaportOrderSold(orderHash, token, tokenId, listPrice);
        } else if (expiry <= block.timestamp) {
            // The order expired before it was filled. We retain the NFT.
            // Revoke seaport approval.
            token.approve(address(0), tokenId);
            emit OpenSeaportOrderExpired(orderHash, token, tokenId, expiry);
        } else {
            // The order hasn't been bought and is still active.
            revert OpenSeaportOrderStillActiveError(orderHash, token, tokenId, expiry);
        }
    }
}
