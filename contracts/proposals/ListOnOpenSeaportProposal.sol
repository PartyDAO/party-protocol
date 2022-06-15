// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC721.sol";

import "./opensea/ISeaportExchange.sol";
import "./ZoraHelpers.sol";
import "./LibProposal.sol";
import "./IProposalExecutionEngine.sol";

// Implements arbitrary call proposals.
abstract contract ListOnOpenSeaportProposal is ZoraHelpers {
    enum OpenSeaportStep {
        None,
        ListedOnZora,
        RetrievedFromZora,
        ListedOnOpenSea
    }

    // ABI-encoded `proposalData` passed into execute.
    struct OpenSeaportProposalData {
        uint256 listPrice;
        uint40 duration;
        IERC721 token;
        uint256 tokenId;
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

    ISeaportExchange public immutable SEAPORT;
    IGlobals private immutable _GLOBALS;

    constructor(IGlobals globals, ISeaportExchange seaport) {
        SEAPORT = seaport;
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
        (OpenSeaportProposalData memory data) = abi.decode(params.proposalData, (OpenSeaportProposalData));
        bool isUnanimous = params.flags & LibProposal.PROPOSAL_FLAG_UNANIMOUS
            == LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        // If there is progressData passed in, we're on the first step,
        // otherwise parse the first 8 bits of the porgressData as the current step.
        OpenSeaportStep step = params.progressData.length == 0
            ? OpenSeaportStep.None
            : abi.decode(params.progressData, (OpenSeaportStep));
        if (step == OpenSeaportStep.None) {
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
                // TODO: Should this be just executionDelay?
                uint40 zoraDuration =
                    uint40(_GLOBALS.getUint256(LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION));
                if (zoraDuration != 0) {
                    (uint256 auctionId, uint40 minExpiry) = _createZoraAuction(
                        data.listPrice,
                        zoraDuration,
                        data.token,
                        data.tokenId
                    );
                    // Return the next step and data required to execute that step.
                    return abi.encode(OpenSeaportStep.ListedOnZora, ZoraProgressData({
                        auctionId: auctionId,
                        minExpiry: minExpiry
                    }));
                }
            }
            // Unanimous vote, not a precious, or no zora duration.
            // Advance past the zora auction phase by pretending we already
            // retrieved it from zora.
            step = OpenSeaportStep.RetrievedFromZora;
        }
        if (step == OpenSeaportStep.ListedOnZora) {
            // The last time this proposal was executed, we listed it on zora.
            // Now retrieve it from zora.
            (, ZoraProgressData memory zpd) =
                abi.decode(params.progressData, (uint8, ZoraProgressData));
            // Try to settle the zora auction. This will revert if the auction
            // is still ongoing.
            if (_settleZoraAuction(zpd.auctionId, zpd.minExpiry)) {
                // Auction sold. Nothing left to do. Return empty progress data
                // to indicate there are no more steps to execute.
                return "";
            }
            // The auction simply expired before anyone bid on it. We have the NFT
            // back now so move on to listing it on opensea immediately.
            step = OpenSeaportStep.RetrievedFromZora;
        }
        if (step == OpenSeaportStep.RetrievedFromZora) {
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
                expiry
            );
            return abi.encode(OpenSeaportStep.ListedOnOpenSea, orderHash, expiry);
        }
        assert(step == OpenSeaportStep.ListedOnOpenSea);
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
        uint256 expiry
    )
        private
        returns (bytes32 orderHash)
    {
        // Approve seaport to spend our NFT. This should revert if we do not own
        // the NFT.
        token.approve(address(SEAPORT), tokenId);

        // Create a (basic) seaport 721 sell order.
        ISeaportExchange.Order[] memory orders = new ISeaportExchange.Order[](1);
        ISeaportExchange.Order memory order = orders[0];
        ISeaportExchange.OrderParameters memory orderParams = order.parameters;
        orderParams.offerer = address(this);
        orderParams.orderType = ISeaportExchange.OrderType.FULL_OPEN;
        orderParams.startTime = block.timestamp;
        orderParams.endTime = expiry;
        assert(orderParams.startTime < orderParams.endTime);
        orderParams.zoneHash = bytes32(0);
        orderParams.salt = 0;
        orderParams.conduitKey = bytes32(0);
        orderParams.totalOriginalConsiderationItems = 1;
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
        orderParams.consideration = new ISeaportExchange.ConsiderationItem[](1);
        {
            ISeaportExchange.ConsiderationItem memory cons = orderParams.consideration[0];
            cons.itemType = ISeaportExchange.ItemType.NATIVE;
            cons.token = address(0);
            cons.identifierOrCriteria = 0;
            cons.startAmount = listPrice;
            cons.endAmount = listPrice;
            cons.recipient = payable(address(this));
        }
        orderHash = _getOrderHash(orderParams);
        // Validate the order on-chain so no signature is required to fill it.
        assert(SEAPORT.validate(orders));
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
