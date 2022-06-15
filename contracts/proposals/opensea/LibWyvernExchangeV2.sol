// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../../tokens/IERC721.sol";

import "./IWyvernExchangeV2.sol";

// Holds the NFT being sold on OS/wyvern.
// This allows parties to list on OS without having to deploy a new personal proxy
// because this contract will be the maker instead of the party.
// https://etherscan.io/address/0x7f268357a8c2552623316e2562d90e642bb538e5#code
// that is shared across all Party instances.
library LibWyvernExchangeV2 {

    bytes4 internal constant SAFE_TRANSFER_FROM_SELECTOR = 0xb88d4fde;

    // Seller should transfer the NFT being sold to this contract
    // (using transferFrom()) before calling this function.
    // LOL VULNS GALORE
    function createSellOrder(
        IWyvernExchangeV2 exchange,
        address maker,
        IERC721 token,
        uint256 tokenId,
        uint256 listPrice,
        uint256 expiry
    )
        internal
        view
        returns (IWyvernExchangeV2.Order memory order)
    {
        // Generate an OS order.
        order = IWyvernExchangeV2.Order({
            exchange: address(exchange),
            maker: maker,
            taker: address(0),
            makerRelayerFee: 0,
            takerRelayerFee: 0, // TODO: necessary for OS to pick up?
            makerProtocolFee: 0,
            takerProtocolFee: 0,
            feeRecipient: address(1), // Must be set for the maker side.
            feeMethod: IWyvernExchangeV2.FeeMethod.SplitFee, // TODO: correct???
            side: IWyvernExchangeV2.Side.Sell,
            saleKind: IWyvernExchangeV2.SaleKind.FixedPrice,
            target: address(token),
            howToCall: IWyvernExchangeV2.HowToCall.Call,
            callData: abi.encodeWithSelector(
                SAFE_TRANSFER_FROM_SELECTOR,
                maker,
                address(0),
                tokenId,
                ""
            ),
            replacementPattern: abi.encodeWithSelector(
                bytes4(0),
                address(0),
                address(type(uint160).max),
                0,
                0,
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
        assert(order.callData.length == order.replacementPattern.length);
    }

    // Compute EIP712 hash of order.
    function hashOrder(IWyvernExchangeV2.Order memory order)
        internal
        pure
        returns (bytes32 hash)
    {
        {
            bytes32 callDataHash = keccak256(order.callData);
            bytes32 replacementPatternHash = keccak256(order.replacementPattern);
            bytes32 staticExtraDataHash = keccak256(order.staticExtraData);
            // Hash in-place.
            // TODO: consider cleaning dirty bits.
            assembly {
                if lt(order, 0x20) {
                    // We overwite the word before `order` so `order` must be at least
                    // a word away from 0.
                    invalid()
                }
                let oldHiddenPrefixField := mload(sub(order, 0x20))
                let oldCallDataField := mload(add(order, 0x1A0))
                let oldReplacementPatternField := mload(add(order, 0x1C0))
                let oldStaticExtraDataField := mload(add(order, 0x200))
                let oldHiddenNonceField := mload(add(order, 0x2E0))
                mstore(
                    sub(order, 0x20),
                    // Order typehash
                    0xdba08a88a748f356e8faf8578488343eab21b1741728779c9dcfdc782bc800f8
                )
                mstore(add(order, 0x1A0), callDataHash)
                mstore(add(order, 0x1C0), replacementPatternHash)
                mstore(add(order, 0x200), staticExtraDataHash)
                mstore(add(order, 0x2E0), 0) // We never increment nonce so it's always 0
                hash := keccak256(sub(order, 0x20), 0x320)
                mstore(sub(order, 0x20), oldHiddenPrefixField)
                mstore(add(order, 0x1A0), oldCallDataField)
                mstore(add(order, 0x1C0), oldReplacementPatternField)
                mstore(add(order, 0x200), oldStaticExtraDataField)
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
            mstore(add(p, 0x22), hash)
            hash := keccak256(p, 0x42)
        }
    }

    function callApproveOrder(IWyvernExchangeV2 exchange, IWyvernExchangeV2.Order memory order)
        internal
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
        exchange.approveOrder_(
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
