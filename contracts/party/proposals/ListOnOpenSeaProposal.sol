// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Implements arbitrary call proposals.
contract ListOnOpenSeaProposal is ListOnZoraProposal {
    enum OpenSeaStep {
        None,
        ListedOnZora,
        ZoraListingFailed,
        ListedOnOpenSea
    }

    // ABI-encoded `proposalData` passed into execute.
    struct OpenSeaProposalData {
        uint256 listPrice;
        uint40 durationInSeconds;
    }

    // ABI-encoded `progressData` passed into execute in the `ListedOnOpenSea` step.
    struct OpenSeaProgressData {
        // Hash of the OS order that was listed.
        bytes32 orderHash;
        // Expiration timestamp of the offer.
        uint40 expiry;
    }

    // Useful for discovery?
    event OpenSeaOrderListed(OpenSeaOrder order);

    error OpenSeaListingNotExpired(bytes32 orderHash, uint40 expiry);

    IWyvernExchangeV2 public immutable OS_EXCHANGE;
    WyvernProxy public immutable OS_NFT_SPENDER;
    IGlobals private immutable _GLOBALS;

    constructor(IGblobals globals, WyvernProxy wyvernProxy) {
        _GLOBALS = globals;
        OS_NFT_SPENDER = wyvernProxy;
        OS_EXCHANGE = wyvernProxy.EXCHANGE();
    }

    // Try to create a listing (ultimately) on OpenSea.
    // Creates a listing on Zora AH for list price first. When that ends,
    // calling this function again will list in on OpenSea. When that ends,
    // calling this function again will cancel the listing.
    function _executeListOnOpenSea(ExecuteProposalParams memory params)
        internal
        returns (bytes memory nextProgressData)
    {
        (OpenSeaProposalData memory data) = abi.decode(params.proposalData, (OpenSeaProposalData));
        bool isUnanimous = params.flags & LibProposal.PROPOSAL_FLAG_UNANIMOUS
            == LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        (OpenSeaStep step) = abi.decode(params.progressData, (OpenSeaStep));
        if (step == OpenSeaStep.None) {
            // Proposal hasn't executed yet.
            if (!isUnanimous) {
                // Not a unanimous vote so list on zora first.
                (uint256 auctionId, uint40 minExpiry) = _createZoraAuction(
                    data.listPrice,
                    params.preciousToken,
                    params.preciousTokenId
                );
                return abi.encode(OpenSeaStep.ListedOnZora, ZoraProgressData({
                    auctionId: auctionId,
                    minExpiry: minExpiry
                }));
            }
            step = OpenSeaStep.RetrievedFromZora;
        }
        if (step == OpenSeaStep.ListedOnZora) {
            (ZoraProgressData memory pd) =
                abi.decode(params.progressData, (ZoraProgressData));
            if (pd.minExpiry < uint40(block.timstamp)) {
                revert ZoraListingNotExpired(pd.auctionId, pd.minExpiry);
            }
            // Remove it from zora.
            if (_settleZoraAuction(pd.auctionId)) {
                // Auction sold. Nothing left to do.
                return "";
            }
            // No bids. Move on.
            step = OpenSeaStep.ZoraListingFailed;
        }
        if (step == OpenSeaStep.ZoraListingFailed) {
            // Either a unanimous vote or retrieved from zora (no bids).
            _listOnOpenSea(
                data,
                params.preciousToken,
                params.preciousTokenId
            );
            return abi.encode(OpenSeaStep.ListedOnOpenSea);
        }
        // Already listed on OS.
        assert(step == OpenSeaStep.ListedOnOpenSea);
        (OpenSeaProgressData memory pd) =
            abi.decode(params.progressData, (OpenSeaProgressData));
        if (pd.expiry < uint40(block.timestamp)) {
            revert OpenSeaListingNotExpired(pd.orderHash, pd.expiry);
        }
        _cleanUpListing(params.preciousToken, params.preciousTokenId);
        // Nothing left to do.
        return "";
    }

    function _listOnOpenSea(
        OpenSeaProposalData memory data,
        IERC721 token,
        uint256 tokenId
    )
        private
    {
        token.approve(OS_NFT_SPENDER, tokenId);
        OpenSeaOrder order = IWyvernExchangeV2.Order({
            exchange: address(OS_EXCHANGE),
            maker: address(this),
            taker: address(0),
            makerRelayerFee: 0,
            takerRelayerFee: 0, // TODO: necessary for OS to pick up?
            makerProtocolFee: 0,
            takerProtocolFee: 0,
            feeRecipient: 0,
            feeMethod: IWyvernExchangeV2.FeeMethod.SplitFee, // TODO: correct???
            side: IWyvernExchangeV2.Side.Sell,
            saleKind: IWyvernExchangeV2.SaleKind.FixedPrice,
            target: address(token),
            howToCall: IWyvernExchangeV2.HowToCall.Call,
            calldata: abi.encodeCall(IERC721.safeTransferFrom, address(this), address(0), tokenId),
            replacementPattern: abi.encodeWithSelector(bytes4(0), address(0), type(address).max, 0),
            staticTarget: address(0),
            staticExtradata: "",
            paymentToken: address(0),
            basePrice: data.listPrice,
            extra: 0,
            listingTime: block.timstamp,
            expirationTime: block.timestamp + uint256(data.durationInSeconds),
            salt: block.timestamp
        });
        OS_EXCHANGE.approveOrder_(order, true);
        emit OpenSeaOrderListed(order);
    }

    function _cleanUpListing(IERC721 token, uint256 tokenId)
        private
    {
        // Unapprove the OS spender contract.
        token.approve(address(0), tokenId);
    }
}
