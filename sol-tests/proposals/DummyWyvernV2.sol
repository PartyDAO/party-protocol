pragma solidity ^0.8;

import "../../contracts/proposals/opensea/IWyvernExchangeV2.sol";

contract DummyRegistry is IWyvernV2MakerProxyRegistry {
    function registerProxy() external returns (address) {
        return address(1);
    }
}

contract DummyWyvernV2 is IWyvernExchangeV2 {
    DummyRegistry private immutable _REGISTRY = new DummyRegistry();

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
    ) external {}

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
        payable
    {}

    function registry() external view returns (IWyvernV2MakerProxyRegistry) {
        return _REGISTRY;
    }

    function cancelledOrFinalized(bytes32 orderHash) external view returns (bool) {
        return false;
    }

    function approvedOrders(bytes32 hash) external view returns (bool approved) {
        return false;
    }

}
