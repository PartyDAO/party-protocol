// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/opensea/IWyvernExchangeV2.sol";
import "../../contracts/proposals/opensea/LibWyvernExchangeV2.sol";

contract OpenSeaTestUtils is Test {

    // Avoid stack too deep.
    struct AtomicMatchArgs {
        address[14] addrs;
        uint256[18] uints;
        uint8[8] feeMethodsSidesKindsHowToCalls;
        uint8[2] vs;
        bytes32[5] rssMetadata;
    }
    IWyvernExchangeV2 private immutable _OS;

    constructor(IWyvernExchangeV2 os) {
        _OS = os;
    }

    function _buyOpenSeaListing(
        IWyvernExchangeV2.Order memory sellOrder,
        address buyer,
        IERC721 token,
        uint256 tokenId
    )
        internal
    {
        IWyvernExchangeV2.Order memory buyOrder = IWyvernExchangeV2.Order({
            exchange: address(_OS),
            maker: buyer,
            taker: address(0),
            makerRelayerFee: 0,
            takerRelayerFee: 0,
            makerProtocolFee: 0,
            takerProtocolFee: 0,
            feeRecipient: address(0),
            feeMethod: IWyvernExchangeV2.FeeMethod.SplitFee,
            side: IWyvernExchangeV2.Side.Buy,
            saleKind: IWyvernExchangeV2.SaleKind.FixedPrice,
            target: address(token),
            howToCall: IWyvernExchangeV2.HowToCall.Call,
            callData: abi.encodeWithSelector(
                LibWyvernExchangeV2.SAFE_TRANSFER_FROM_SELECTOR,
                sellOrder.maker,
                buyer,
                tokenId,
                ""
            ),
            replacementPattern: "",
            staticTarget: address(0),
            staticExtraData: "",
            paymentToken: address(0),
            basePrice: sellOrder.basePrice,
            extra: 0,
            listingTime: sellOrder.listingTime,
            expirationTime: 0,
            salt: 0
        });
        assert(sellOrder.callData.length == buyOrder.callData.length);
        _callAtomicMatch(sellOrder, buyOrder);
    }

    function _callAtomicMatch(
        IWyvernExchangeV2.Order memory sellOrder,
        IWyvernExchangeV2.Order memory buyOrder
    )
        internal
    {
        AtomicMatchArgs memory args;
        args.addrs[0] = buyOrder.exchange;
        args.addrs[1] = buyOrder.maker;
        args.addrs[2] = buyOrder.taker;
        args.addrs[3] = buyOrder.feeRecipient;
        args.addrs[4] = buyOrder.target;
        args.addrs[5] = buyOrder.staticTarget;
        args.addrs[6] = buyOrder.paymentToken;
        args.addrs[7] = sellOrder.exchange;
        args.addrs[8] = sellOrder.maker;
        args.addrs[9] = sellOrder.taker;
        args.addrs[10] = sellOrder.feeRecipient;
        args.addrs[11] = sellOrder.target;
        args.addrs[12] = sellOrder.staticTarget;
        args.addrs[13] = sellOrder.paymentToken;
        args.uints[0] = buyOrder.makerRelayerFee;
        args.uints[1] = buyOrder.takerRelayerFee;
        args.uints[2] = buyOrder.makerProtocolFee;
        args.uints[3] = buyOrder.takerProtocolFee;
        args.uints[4] = buyOrder.basePrice;
        args.uints[5] = buyOrder.extra;
        args.uints[6] = buyOrder.listingTime;
        args.uints[7] = buyOrder.expirationTime;
        args.uints[8] = buyOrder.salt;
        args.uints[9] = sellOrder.makerRelayerFee;
        args.uints[10] = sellOrder.takerRelayerFee;
        args.uints[11] = sellOrder.makerProtocolFee;
        args.uints[12] = sellOrder.takerProtocolFee;
        args.uints[13] = sellOrder.basePrice;
        args.uints[14] = sellOrder.extra;
        args.uints[15] = sellOrder.listingTime;
        args.uints[16] = sellOrder.expirationTime;
        args.uints[17] = sellOrder.salt;
        args.feeMethodsSidesKindsHowToCalls[0] = uint8(buyOrder.feeMethod);
        args.feeMethodsSidesKindsHowToCalls[1] = uint8(buyOrder.side);
        args.feeMethodsSidesKindsHowToCalls[2] = uint8(buyOrder.saleKind);
        args.feeMethodsSidesKindsHowToCalls[3] = uint8(buyOrder.howToCall);
        args.feeMethodsSidesKindsHowToCalls[4] = uint8(sellOrder.feeMethod);
        args.feeMethodsSidesKindsHowToCalls[5] = uint8(sellOrder.side);
        args.feeMethodsSidesKindsHowToCalls[6] = uint8(sellOrder.saleKind);
        args.feeMethodsSidesKindsHowToCalls[7] = uint8(sellOrder.howToCall);
        // Neither side uses signatures.
        // Neither side uses metadata.
        // TODO: This is probably wrong for split fees.
        uint256 totalCost =
            buyOrder.basePrice + buyOrder.takerRelayerFee + buyOrder.takerProtocolFee;
        hoax(buyOrder.maker, totalCost);
        _OS.atomicMatch_{ value: totalCost }(
            args.addrs,
            args.uints,
            args.feeMethodsSidesKindsHowToCalls,
            buyOrder.callData,
            sellOrder.callData,
            buyOrder.replacementPattern,
            sellOrder.replacementPattern,
            buyOrder.staticExtraData,
            sellOrder.staticExtraData,
            args.vs,
            args.rssMetadata
        );
    }
}
