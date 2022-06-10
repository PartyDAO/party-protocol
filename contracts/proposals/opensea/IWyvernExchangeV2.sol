// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./IWyvernV2MakerProxyRegistry.sol";

// Based on https://etherscan.io/address/0x7f268357a8c2552623316e2562d90e642bb538e5#code

interface IWyvernExchangeV2 {

     /* An ECDSA signature. */
    struct Sig {
        /* v parameter */
        uint8 v;
        /* r parameter */
        bytes32 r;
        /* s parameter */
        bytes32 s;
    }

    enum FeeMethod { ProtocolFee, SplitFee }
    enum Side { Buy, Sell }
    enum SaleKind { FixedPrice, DutchAuction }
    enum HowToCall { Call, DelegateCall }

     /* An order on the exchange. */
    struct Order {
        /* Exchange address, intended as a versioning mechanism. */
        address exchange;
        /* Order maker address. */
        address maker;
        /* Order taker address, if specified. */
        address taker;
        /* Maker relayer fee of the order, unused for taker order. */
        uint256 makerRelayerFee;
        /* Taker relayer fee of the order, or maximum taker fee for a taker order. */
        uint256 takerRelayerFee;
        /* Maker protocol fee of the order, unused for taker order. */
        uint256 makerProtocolFee;
        /* Taker protocol fee of the order, or maximum taker fee for a taker order. */
        uint256 takerProtocolFee;
        /* Order fee recipient or zero address for taker order. */
        address feeRecipient;
        /* Fee method (protocol token or split fee). */
        FeeMethod feeMethod;
        /* Side (buy/sell). */
        Side side;
        /* Kind of sale. */
        SaleKind saleKind;
        /* Target. */
        address target;
        /* HowToCall. */
        HowToCall howToCall;
        /* Calldata. */
        bytes callData; // Offset 13
        /* Calldata replacement pattern, or an empty byte array for no replacement. */
        bytes replacementPattern; // Offset 14
        /* Static call target, zero-address for no static call. */
        address staticTarget;
        /* Static call extra data. */
        bytes staticExtraData; // Offset 16
        /* Token used to pay for the order, or the zero-address as a sentinel value for Ether. */
        address paymentToken;
        /* Base price of the order (in paymentTokens). */
        uint256 basePrice;
        /* Auction extra parameter - minimum bid increment for English auctions, starting/ending price difference. */
        uint256 extra;
        /* Listing timestamp. */
        uint256 listingTime;
        /* Expiration timestamp - 0 for no expiry. */
        uint256 expirationTime;
        /* Order salt, used to prevent duplicate hashes. */
        uint256 salt;
    }

    function approveOrder_(
        address[7] memory addrs,
        uint256[9] memory uints,
        FeeMethod feeMethod,
        Side side,
        SaleKind saleKind,
        HowToCall howToCall,
        bytes memory callData,
        bytes memory replacementPattern,
        bytes memory staticExtraData,
        bool orderbookInclusionDesired
    ) external;
    function atomicMatch_(
        address[14] memory addrs,
        uint256[18] memory uints,
        uint8[8] memory feeMethodsSidesKindsHowToCalls,
        bytes memory callDataBuy,
        bytes memory callDataSell,
        bytes memory replacementPatternBuy,
        bytes memory replacementPatternSell,
        bytes memory staticExtraDataBuy,
        bytes memory staticExtraDataSell,
        uint8[2] memory vs,
        bytes32[5] memory rssMetadata
    )
        external
        payable;
    function registry() external view returns (IWyvernV2MakerProxyRegistry);
    function cancelledOrFinalized(bytes32 orderHash) external view returns (bool);
    function approvedOrders(bytes32 hash) external view returns (bool approved);
}
