// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Holds the NFT being sold on OS/wyvern.
// This allows parties to list on OS without having to deploy a new personal proxy
// because this contract will be the maker instead of the party.
// https://etherscan.io/address/0x7f268357a8c2552623316e2562d90e642bb538e5#code
// that is shared across all Party instances.
contract SharedWyvernV2Maker {
    using LibRawResult for bytes;

    error NoDirectCallsError();
    error InvalidProofError(address notOwner, address owner);
    error ListingAlreadyExistsError(IERC721 token, uint256 tokenId);
    error TokenNotOwnedError(IERC721 token, uint256 tokenId);

    event OpenSeaOrderListed(
        address seller,
        IERC721 token,
        uint256 tokenId,
        IWyvernExchangeV2.Order order
    );
    event OpenSeaOrderSold(
        bytes32 orderHash,
        address owner,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice
    );
    event OpenSeaOrderExpired(
        bytes32 orderHash,
        address owner,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice
    );
    event OpenSeaOrderStillActiveError(bytes32 orderHash);

    IWyvernExchangeV2 public immutable EXCHANGE;
    address public immutable TRANSFER_PROXY;

    mapping (IERC721 => mapping (uint256 => bytes32)) proofsByNft;

    modifer noDirectCalls() {
        if (tx.origin == msg.sender) {
            revert NoDirectCallsError();
        }
        _;
    }

    constructor(IWyvernExchangeV2 exchange) {
        EXCHANGE = exchange;
        // OS/wyvern requires each maker to have their own "proxy" which
        // handles the transferring of the NFT during settlement.
        TRANSFER_PROXY = EXCHANGE.registry().registerProxy();
    }

    // Seller should transfer the NFT being sold to this contract
    // (using transferFrom()) before calling this function.
    // LOL VULNS GALORE
    function createListing(
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint256 expiry
    )
        external
        noDirectCalls
        returns (bytes32 orderHash)
    {
        if (proofsByNft[token][tokenId] != 0x0) {
            revert ListingAlreadyExistsError(token, tokenId);
        }
        if (token.ownerOf(tokenId) != address(this)) {
            // Should also revert on token.approve()
            revert TokenNotOwnedError(token, tokenId);
        }
        IWyvernExchangeV2.Order memory order = IWyvernExchangeV2.Order({
            exchange: address(EXCHANGE),
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
            calldata: abi.encodeCall(
                IERC721.safeTransferFrom,
                address(this),
                address(0),
                tokenId
            ),
            replacementPattern: abi.encodeWithSelector(
                bytes4(0),
                address(0),
                type(address).max,
                0
            ),
            staticTarget: address(0),
            staticExtradata: "",
            paymentToken: address(0),
            basePrice: data.listPrice,
            extra: 0,
            listingTime: block.timstamp,
            expirationTime: expiry,
            salt: block.timestamp
        });
        orderHash = _hashOrder(order);
        proofsByNft[token][tokenId] = _toProof(msg.sender, token, tokenId, listPrice);
        EXCHANGE.approveOrder_(order, true);
        token.approve(address(TRANSFER_PROXY), tokenId);
        emit OpenSeaOrderListed(msg.sender, token, tokenId, order);
    }

    // Callable once the listing has expired or has been filled.
    function finalizeListing(
        bytes32 orderHash,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint256 expiry
    )
        external
        noDirectCalls
    {
        {
            // Make sure all details form the correct proof for this NFT.
            bytes32 proof = _toProof(msg.sender, orderHash, listPrice, expiry);
            if (proofsByNft[token][tokenId] != proof) {
                revert InvalidProofError(msg.sender, owner);
            }
        }
        proofsByNft[token][tokenId] = 0x0; // No claiming twice.
        if (EXCHANGE.cancelledOrFinalized(orderHash)) {
            // We never cancel so it must have been filled.
            // Pay out the listPrice to sender.
            payable(msg.sender).call{ value: listPrice }("");
            emit OpenSeaOrderSold(orderHash, msg.sender, token, tokenId, listPrice);
        } else if (expiry <= block.timestamp) {
            // Listing expired.
            // Revoke approval.
            token.approve(address(0), tokenId);
            // Transfer the NFT back to msg.sender.
            token.transferFrom(address(this), msg.sender, tokenId);
            emit OpenSeaOrderExpired(orderHash, msg.sender, token, tokenId, listPrice);
        } else {
            revert OpenSeaOrderStillActiveError(orderHash);
        }
    }

    function _toProof(
        address owner,
        bytes32 orderHash
        uint256 listPrice,
        uint256 expiry
    )
        private
        pure
        returns (bytes32 proof)
    {
        assembly {
            let p := mload(0x40)
            mstore(p, owner)
            mstore(add(p, 0x20), orderHash)
            mstore(add(p, 0x40), listPrice)
            mstore(add(p, 0x60), expiry)
            proof := keccak256(p, 0x80)
        }
    }

    function _hashOrder(IWyvernExchangeV2.Order memory order)
        internal
        pure
    returns (bytes32 hash)
    {
        // ...
    }
}
