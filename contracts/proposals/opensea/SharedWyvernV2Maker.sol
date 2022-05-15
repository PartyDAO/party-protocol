// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../../utils/LibRawResult.sol";
import "../../utils/LibAddress.sol";
import "../../tokens/ERC721Receiver.sol";
import "../../tokens/IERC721.sol";

import "./IWyvernExchangeV2.sol";

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

    bytes4 private constant SAFE_TRANSFER_FROM_SELECTOR = 0xb88d4fde;

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
        IWyvernExchangeV2.Order memory order = IWyvernExchangeV2.Order({
            exchange: address(EXCHANGE),
            maker: address(this),
            taker: address(0),
            makerRelayerFee: 0,
            takerRelayerFee: 0, // TODO: necessary for OS to pick up?
            makerProtocolFee: 0,
            takerProtocolFee: 0,
            feeRecipient: address(0),
            feeMethod: IWyvernExchangeV2.FeeMethod.SplitFee, // TODO: correct???
            side: IWyvernExchangeV2.Side.Sell,
            saleKind: IWyvernExchangeV2.SaleKind.FixedPrice,
            target: address(token),
            howToCall: IWyvernExchangeV2.HowToCall.Call,
            callData: abi.encodeWithSelector(
                SAFE_TRANSFER_FROM_SELECTOR,
                address(this),
                address(0),
                tokenId,
                ""
            ),
            replacementPattern: abi.encodeWithSelector(
                bytes4(0),
                address(0),
                address(type(uint160).max),
                0
            ),
            staticTarget: address(0),
            staticExtraData: "",
            paymentToken: address(0),
            basePrice: listPrice,
            extra: 0,
            listingTime: block.timestamp,
            expirationTime: expiry,
            salt: block.timestamp
        });
        orderHash = _hashOrder(order);
        proofsByNft[token][tokenId] =
            _toProof(msg.sender, orderHash, listPrice, expiry);
        token.approve(address(TRANSFER_PROXY), tokenId);
        _callApproveOrder(order);
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

    // Compute EIP712 hash of order.
    function _hashOrder(IWyvernExchangeV2.Order memory order)
        internal
        pure
        returns (bytes32 hash)
    {
        {
            bytes32 callDataHash = keccak256(order.callData);
            bytes32 replacementPatternHash = keccak256(order.replacementPattern);
            bytes32 staticExtraData = keccak256(order.staticExtraData);
            // Hash in-place.
            // TODO: consider cleaning dirty bits.
            assembly {
                if lt(order, 0x20) {
                    // We overwite the word before `order` so `order` must be at least
                    // a word away from 0.
                    invalid()
                }
                let oldHiddenPrefixField := mload(sub(order, 0x20))
                let oldCallDataField := mload(add(order, 0x1C0))
                let oldReplacementPatternField := mload(add(order, 0x1E0))
                let oldStaticExtraDataField := mload(add(order, 0x220))
                let oldHiddenNonceField := mload(add(order, 0x2E0))
                mstore(
                    sub(order, 0x20),
                    // Order typehash
                    0xdba08a88a748f356e8faf8578488343eab21b1741728779c9dcfdc782bc800f8
                )
                mstore(add(order, 0x1C0), callDataHash)
                mstore(add(order, 0x1E0), replacementPatternHash)
                mstore(add(order, 0x220), staticExtraData)
                mstore(add(order, 0x2E0), 0) // We never increment nonce so it's always 0
                hash := keccak256(order, 0x300)
                mstore(sub(order, 0x20), oldHiddenPrefixField)
                mstore(add(order, 0x1C0), oldCallDataField)
                mstore(add(order, 0x1E0), oldReplacementPatternField)
                mstore(add(order, 0x220), oldStaticExtraDataField)
                mstore(add(order, 0x2E0), oldHiddenNonceField)
            }
        }
        // Equivalent to:
        //   keccak256(
        //    abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hashOrder(order, nonce))
        //   );
        assembly {
            let p := mload(0x40)
            mstore(p, 0x1901000000000000000000000000000000000000000000000000000000000000)
            mstore(
                add(p, 0x02),
                0x72982d92449bfb3d338412ce4738761aff47fb975ceb17a1bc3712ec716a5a68
            )
            mstore(add(p, 0x34), hash)
            hash := keccak256(p, 0x46)
        }
    }

    function _callApproveOrder(IWyvernExchangeV2.Order memory order)
        private
    {
        address[7] memory addrs;
        addrs[0] = address(order.exchange);
        addrs[1] = address(order.maker);
        addrs[2] = address(order.taker);
        addrs[3] = address(order.feeRecipient);
        addrs[4] = address(order.target);
        addrs[5] = address(order.staticTarget);
        addrs[6] = address(order.paymentToken);
        uint256[9] memory uints;
        uints[0] = order.makerRelayerFee;
        uints[1] = order.takerRelayerFee;
        uints[2] = order.makerProtocolFee;
        uints[3] = order.takerProtocolFee;
        uints[4] = order.basePrice;
        uints[5] = order.extra;
        uints[6] = order.listingTime;
        uints[7] = order.expirationTime;
        uints[8] = order.salt;
        EXCHANGE.approveOrder_(
            addrs,
            uints,
            order.feeMethod,
            order.side,
            order.saleKind,
            order.howToCall,
            order.callData,
            order.replacementPattern,
            order.staticExtraData,
            true
        );
    }
}
