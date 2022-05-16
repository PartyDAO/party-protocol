// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../../utils/LibRawResult.sol";
import "../../utils/LibAddress.sol";
import "../../tokens/ERC721Receiver.sol";
import "../../tokens/IERC721.sol";

import "./IWyvernExchangeV2.sol";
import "./LibWyvernExchangeV2.sol";

// Holds the NFT being sold on OS/wyvern.
// This allows parties to list on OS without having to deploy a new personal proxy
// because this contract will be the maker instead of the party.
// https://etherscan.io/address/0x7f268357a8c2552623316e2562d90e642bb538e5#code
// that is shared across all Party instances.
contract SharedWyvernV2Maker is ERC721Receiver {
    using LibRawResult for bytes;
    using LibAddress for address payable;

    error NoDirectCallsError();
    error InvalidProofError(address notOwner, bytes32 orderHash, uint256 listPrice, uint256 expiry);
    error ListingAlreadyExistsError(IERC721 token, uint256 tokenId);
    error TokenNotOwnedError(IERC721 token, uint256 tokenId);
    error OpenSeaOrderStillActiveError(bytes32 orderHash);

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

    IWyvernExchangeV2 public immutable EXCHANGE;
    address public immutable TRANSFER_PROXY;

    mapping (IERC721 => mapping (uint256 => bytes32)) proofsByNft;

    modifier noDirectCalls() {
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

    receive() external payable {}

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
            // Should also revert on token.approve() so perhaps not necessary.
            revert TokenNotOwnedError(token, tokenId);
        }
        // Generate an OS order.
        IWyvernExchangeV2.Order memory order = LibWyvernExchangeV2.createSellOrder(
            EXCHANGE,
            address(this),
            token,
            tokenId,
            listPrice,
            expiry
        );
        orderHash = LibWyvernExchangeV2.hashOrder(order);
        proofsByNft[token][tokenId] =
            _toProof(msg.sender, orderHash, listPrice, expiry);
        token.approve(address(TRANSFER_PROXY), tokenId);
        LibWyvernExchangeV2.callApproveOrder(EXCHANGE, order);
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
                revert InvalidProofError(msg.sender, orderHash, listPrice, expiry);
            }
        }
        proofsByNft[token][tokenId] = 0x0; // No claiming twice.
        if (EXCHANGE.cancelledOrFinalized(orderHash)) {
            // We never cancel so it must have been filled.
            // Pay out the listPrice to sender.
            payable(msg.sender).transferEth(listPrice);
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
        bytes32 orderHash,
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
}
