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
    address partyDaoMultisig;
    address zoraAuctionHouseAddress;
    address osZone;
    bytes32 osConduitKey;
    address osConduitController;
    address fractionalVaultFactory;
    string networkName;
  }

  function rinkeby(address multisig) internal pure returns (DeployConstants memory) {
    DeployConstants memory deployConstants = DeployConstants({
      seaportExchangeAddress: 0x00000000006c3852cbEf3e08E8dF289169EdE581,
      osZoraAuctionDuration: 2 minutes,
      osZoraAuctionTimeout: 2 minutes,
      osMinOrderDuration: 2 minutes,
      osMaxOrderDuration: 14 days,
      zoraMinAuctionDuration: 2 minutes,
      zoraMaxAuctionDuration: 10 days,
      zoraMaxAuctionTimeout: 7 days,
      partyDaoMultisig: multisig,
      zoraAuctionHouseAddress: 0xE7dd1252f50B3d845590Da0c5eADd985049a03ce,
      osZone: 0x0000000000000000000000000000000000000000,
      osConduitKey: 0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000,
      osConduitController: 0x00000000F9490004C11Cef243f5400493c00Ad63,
      fractionalVaultFactory: 0x09EB641BA93CfA6340E944a22bDd2F1C8c745A9f,
      networkName: 'rinkeby'
    });

    return deployConstants;
  }

  function goerli(address multisig) internal pure returns (DeployConstants memory) {
    DeployConstants memory deployConstants = DeployConstants({
      seaportExchangeAddress: 0x00000000006c3852cbEf3e08E8dF289169EdE581,
      osZoraAuctionDuration: 2 minutes,
      osZoraAuctionTimeout: 2 minutes,
      osMinOrderDuration: 2 minutes,
      osMaxOrderDuration: 14 days,
      zoraMinAuctionDuration: 2 minutes,
      zoraMaxAuctionDuration: 10 days,
      zoraMaxAuctionTimeout: 7 days,
      partyDaoMultisig: multisig,
      zoraAuctionHouseAddress: 0x6a6Cdb103f1072E0aFeADAC9BeBD6E14B287Ca57,
      osZone: 0x00000000E88FE2628EbC5DA81d2b3CeaD633E89e,
      osConduitKey: 0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000,
      osConduitController: 0x00000000F9490004C11Cef243f5400493c00Ad63,
      networkName: 'goerli',
      fractionalVaultFactory: 0x014850E83d9D0D1BB0c8624035F09626b967B81c
    });

    return deployConstants;
  }

  function mainnet() internal pure returns (DeployConstants memory) {
    // TODO: chec these values
    DeployConstants memory deployConstants = DeployConstants({
      seaportExchangeAddress: 0x00000000006c3852cbEf3e08E8dF289169EdE581,
      osZoraAuctionDuration: 2 minutes,
      osZoraAuctionTimeout: 2 minutes,
      osMinOrderDuration: 2 minutes,
      osMaxOrderDuration: 14 days,
      zoraMinAuctionDuration: 2 minutes,
      zoraMaxAuctionDuration: 10 days,
      zoraMaxAuctionTimeout: 7 days,
      partyDaoMultisig: 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f,
      zoraAuctionHouseAddress: 0xE468cE99444174Bd3bBBEd09209577d25D1ad673,
      osZone: 0x0000000000000000000000000000000000000000,
      osConduitKey: 0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000,
      osConduitController: 0x00000000F9490004C11Cef243f5400493c00Ad63,
      networkName: 'mainnet',
      fractionalVaultFactory: 0x85Aa7f78BdB2DE8F3e0c0010d99AD5853fFcfC63
    });

    return deployConstants;
  }
}
