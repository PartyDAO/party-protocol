// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

library LibDeployConstants {
    uint256 internal constant PARTY_DAO_DISTRIBUTION_SPLIT_BPS = 250;

    struct DeployConstants {
        address seaportExchangeAddress;
        uint256 osZoraAuctionDuration;
        uint256 osZoraAuctionTimeout;
        uint256 osMinOrderDuration;
        uint256 osMaxOrderDuration;
        uint256 zoraMinAuctionDuration;
        uint256 zoraMaxAuctionDuration;
        uint256 zoraMaxAuctionTimeout;
        uint256 minCancelDelay;
        uint256 maxCancelDelay;
        uint40 distributorEmergencyActionAllowedDuration;
        address partyDaoMultisig;
        address[] allowedERC20SwapOperatorTargets;
        address osZone;
        bytes32 osConduitKey;
        address osConduitController;
        address fractionalVaultFactory;
        address nounsAuctionHouse;
        address zoraReserveAuctionCoreEth;
        string networkName;
        address deployedNounsMarketWrapper;
        uint96 contributionRouterInitialFee;
        address tokenDistributorV1;
        address tokenDistributorV2;
        address tokenDistributorV3;
        string baseExternalURL;
    }

    function sepolia(address multisig) internal pure returns (DeployConstants memory) {
        address[] memory allowedERC20SwapOperatorTargets = new address[](0);

        DeployConstants memory deployConstants = DeployConstants({
            seaportExchangeAddress: 0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC,
            osZoraAuctionDuration: 2 minutes,
            osZoraAuctionTimeout: 2 minutes,
            osMinOrderDuration: 2 minutes,
            osMaxOrderDuration: 14 days,
            zoraMinAuctionDuration: 2 minutes,
            zoraMaxAuctionDuration: 10 days,
            zoraMaxAuctionTimeout: 7 days,
            minCancelDelay: 5 minutes,
            maxCancelDelay: 1 days,
            distributorEmergencyActionAllowedDuration: 365 days,
            partyDaoMultisig: multisig,
            allowedERC20SwapOperatorTargets: allowedERC20SwapOperatorTargets,
            osZone: 0x0000000000000000000000000000000000000000,
            osConduitKey: 0xf984c55ca75735630c1c27d3d06969c1aa6af1df86d22ddc0e3a978ad6138e9f,
            osConduitController: 0x00000000F9490004C11Cef243f5400493c00Ad63,
            fractionalVaultFactory: 0x0000000000000000000000000000000000000000,
            nounsAuctionHouse: 0x0000000000000000000000000000000000000000,
            zoraReserveAuctionCoreEth: 0x0000000000000000000000000000000000000000,
            networkName: "sepolia",
            deployedNounsMarketWrapper: 0x0000000000000000000000000000000000000000,
            contributionRouterInitialFee: 0.00055 ether,
            tokenDistributorV1: 0x0000000000000000000000000000000000000000,
            tokenDistributorV2: 0x0000000000000000000000000000000000000000,
            tokenDistributorV3: 0xf0560F963538017CAA5081D96f839FE5D265acCB,
            baseExternalURL: "https://party.app/party/"
        });

        return deployConstants;
    }

    function baseSepolia(address multisig) internal pure returns (DeployConstants memory) {
        address[] memory allowedERC20SwapOperatorTargets = new address[](0);

        DeployConstants memory deployConstants = DeployConstants({
            seaportExchangeAddress: 0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC,
            osZoraAuctionDuration: 2 minutes,
            osZoraAuctionTimeout: 2 minutes,
            osMinOrderDuration: 2 minutes,
            osMaxOrderDuration: 14 days,
            zoraMinAuctionDuration: 2 minutes,
            zoraMaxAuctionDuration: 10 days,
            zoraMaxAuctionTimeout: 7 days,
            minCancelDelay: 5 minutes,
            maxCancelDelay: 1 days,
            distributorEmergencyActionAllowedDuration: 365 days,
            partyDaoMultisig: multisig,
            allowedERC20SwapOperatorTargets: allowedERC20SwapOperatorTargets,
            osZone: 0x0000000000000000000000000000000000000000,
            osConduitKey: 0xf984c55ca75735630c1c27d3d06969c1aa6af1df86d22ddc0e3a978ad6138e9f,
            osConduitController: 0x00000000F9490004C11Cef243f5400493c00Ad63,
            fractionalVaultFactory: 0x0000000000000000000000000000000000000000,
            nounsAuctionHouse: 0x0000000000000000000000000000000000000000,
            zoraReserveAuctionCoreEth: 0x0000000000000000000000000000000000000000,
            networkName: "base-sepolia",
            deployedNounsMarketWrapper: 0x0000000000000000000000000000000000000000,
            contributionRouterInitialFee: 0.00055 ether,
            tokenDistributorV1: 0x0000000000000000000000000000000000000000,
            tokenDistributorV2: 0x0000000000000000000000000000000000000000,
            tokenDistributorV3: 0x2d451d8317feF4f3fB8798815520202195FE8C7C,
            baseExternalURL: "https://party.app/party/"
        });

        return deployConstants;
    }

    function mainnet() internal pure returns (DeployConstants memory) {
        address[] memory allowedERC20SwapOperatorTargets = new address[](1);
        allowedERC20SwapOperatorTargets[0] = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; // 0x Swap Aggregator

        DeployConstants memory deployConstants = DeployConstants({
            seaportExchangeAddress: 0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC,
            osZoraAuctionDuration: 1 days,
            osZoraAuctionTimeout: 1 days,
            osMinOrderDuration: 1 hours,
            osMaxOrderDuration: 4 weeks,
            zoraMinAuctionDuration: 1 days,
            zoraMaxAuctionDuration: 4 weeks,
            zoraMaxAuctionTimeout: 2 weeks,
            minCancelDelay: 6 weeks,
            maxCancelDelay: 12 weeks,
            distributorEmergencyActionAllowedDuration: 365 days,
            partyDaoMultisig: 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f,
            allowedERC20SwapOperatorTargets: allowedERC20SwapOperatorTargets,
            osZone: 0x0000000000000000000000000000000000000000,
            osConduitKey: 0xf984c55ca75735630c1c27d3d06969c1aa6af1df86d22ddc0e3a978ad6138e9f,
            osConduitController: 0x00000000F9490004C11Cef243f5400493c00Ad63,
            fractionalVaultFactory: 0x85Aa7f78BdB2DE8F3e0c0010d99AD5853fFcfC63,
            nounsAuctionHouse: 0x830BD73E4184ceF73443C15111a1DF14e495C706,
            zoraReserveAuctionCoreEth: 0x5f7072E1fA7c01dfAc7Cf54289621AFAaD2184d0,
            networkName: "mainnet",
            deployedNounsMarketWrapper: 0x9319DAd8736D752C5c72DB229f8e1b280DC80ab1,
            contributionRouterInitialFee: 0.00055 ether,
            tokenDistributorV1: 0x1CA2007a81F8A7491BB6E11D8e357FD810896454,
            tokenDistributorV2: 0x49a3caab781f711aD74C9d2F34c3cbD835d6A608,
            tokenDistributorV3: 0x8723b021b008dd370fbec1c791c390a2bc957654,
            baseExternalURL: "https://party.app/party/"
        });

        return deployConstants;
    }

    function base() internal pure returns (DeployConstants memory) {
        address[] memory allowedERC20SwapOperatorTargets = new address[](1);
        allowedERC20SwapOperatorTargets[0] = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; // 0x Swap Aggregator

        DeployConstants memory deployConstants = DeployConstants({
            seaportExchangeAddress: 0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC,
            osZoraAuctionDuration: 1 days,
            osZoraAuctionTimeout: 1 days,
            osMinOrderDuration: 1 hours,
            osMaxOrderDuration: 4 weeks,
            zoraMinAuctionDuration: 1 days,
            zoraMaxAuctionDuration: 4 weeks,
            zoraMaxAuctionTimeout: 2 weeks,
            minCancelDelay: 6 weeks,
            maxCancelDelay: 12 weeks,
            distributorEmergencyActionAllowedDuration: 365 days,
            partyDaoMultisig: 0xF498fd75Ee8D35294952343f1A77CAE5EA5aF6AA,
            allowedERC20SwapOperatorTargets: allowedERC20SwapOperatorTargets,
            osZone: 0x0000000000000000000000000000000000000000,
            osConduitKey: 0xf984c55ca75735630c1c27d3d06969c1aa6af1df86d22ddc0e3a978ad6138e9f,
            osConduitController: 0x00000000F9490004C11Cef243f5400493c00Ad63,
            fractionalVaultFactory: 0x0000000000000000000000000000000000000000,
            nounsAuctionHouse: 0x0000000000000000000000000000000000000000,
            zoraReserveAuctionCoreEth: 0x0000000000000000000000000000000000000000,
            networkName: "base",
            deployedNounsMarketWrapper: 0x0000000000000000000000000000000000000000,
            contributionRouterInitialFee: 0.00055 ether,
            tokenDistributorV1: address(0),
            tokenDistributorV2: 0xf0560F963538017CAA5081D96f839FE5D265acCB,
            tokenDistributorV3: 0x6c7d98079023F05c2B57DFc933fa0903A2C95411,
            baseExternalURL: "https://base.party.app/party/"
        });

        return deployConstants;
    }

    function zora() internal pure returns (DeployConstants memory) {
        address[] memory allowedERC20SwapOperatorTargets = new address[](0);

        DeployConstants memory deployConstants = DeployConstants({
            seaportExchangeAddress: 0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC,
            osZoraAuctionDuration: 1 days,
            osZoraAuctionTimeout: 1 days,
            osMinOrderDuration: 1 hours,
            osMaxOrderDuration: 4 weeks,
            zoraMinAuctionDuration: 1 days,
            zoraMaxAuctionDuration: 4 weeks,
            zoraMaxAuctionTimeout: 2 weeks,
            minCancelDelay: 6 weeks,
            maxCancelDelay: 12 weeks,
            distributorEmergencyActionAllowedDuration: 365 days,
            partyDaoMultisig: 0x1B059499F194B3ec0c754b3c8DEb0Ec91b0e68e9,
            allowedERC20SwapOperatorTargets: allowedERC20SwapOperatorTargets,
            osZone: 0x0000000000000000000000000000000000000000,
            osConduitKey: 0xf984c55ca75735630c1c27d3d06969c1aa6af1df86d22ddc0e3a978ad6138e9f,
            osConduitController: 0x00000000F9490004C11Cef243f5400493c00Ad63,
            fractionalVaultFactory: 0x0000000000000000000000000000000000000000,
            nounsAuctionHouse: 0x0000000000000000000000000000000000000000,
            zoraReserveAuctionCoreEth: 0x0000000000000000000000000000000000000000,
            networkName: "zora",
            deployedNounsMarketWrapper: 0x0000000000000000000000000000000000000000,
            contributionRouterInitialFee: 0.00055 ether,
            tokenDistributorV1: address(0),
            tokenDistributorV2: address(0),
            tokenDistributorV3: 0x9a85aD6eb642bd1409df73484B331a1925B6c6cd,
            baseExternalURL: "https://zora.party.app/party/"
        });

        return deployConstants;
    }
}
