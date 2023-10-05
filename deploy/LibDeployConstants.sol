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
        address oldTokenDistributor;
        string baseExternalURL;
    }

    function goerli(address multisig) internal pure returns (DeployConstants memory) {
        address[] memory allowedERC20SwapOperatorTargets = new address[](1);
        allowedERC20SwapOperatorTargets[0] = 0xF91bB752490473B8342a3E964E855b9f9a2A668e; // 0x Swap Aggregator

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
            fractionalVaultFactory: 0x014850E83d9D0D1BB0c8624035F09626b967B81c,
            nounsAuctionHouse: 0x7295e70f2B26986Ba108bD1Bf9E349a181F4a6Ea,
            zoraReserveAuctionCoreEth: 0x2506D9F5A2b0E1A2619bCCe01CD3e7C289A13163,
            networkName: "goerli",
            deployedNounsMarketWrapper: 0x0000000000000000000000000000000000000000,
            contributionRouterInitialFee: 0.00055 ether,
            oldTokenDistributor: address(0),
            baseExternalURL: "https://party.app/party/"
        });

        return deployConstants;
    }

    function baseGoerli(address multisig) internal pure returns (DeployConstants memory) {
        address[] memory allowedERC20SwapOperatorTargets = new address[](1);
        allowedERC20SwapOperatorTargets[0] = 0xF91bB752490473B8342a3E964E855b9f9a2A668e; // 0x Swap Aggregator

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
            networkName: "base-goerli",
            deployedNounsMarketWrapper: 0x0000000000000000000000000000000000000000,
            contributionRouterInitialFee: 0.00055 ether,
            oldTokenDistributor: address(0),
            baseExternalURL: "https://base.party.app/party/"
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
            oldTokenDistributor: 0x1CA2007a81F8A7491BB6E11D8e357FD810896454,
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
            oldTokenDistributor: address(0),
            baseExternalURL: "https://base.party.app/party/"
        });

        return deployConstants;
    }
}
