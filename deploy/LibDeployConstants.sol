// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

library LibDeployConstants {
  uint256 internal constant PARTY_DAO_DISTRIBUTION_SPLIT_BPS = 250;

  struct DeployConstants {
    address[5] adminAddresses; // todo: change size of array based on deploy
    address seaportExchangeAddress;
    uint256 osZoraAuctionDuration;
    uint256 osZoraAuctionTimeout;
    uint256 osMinOrderDuration;
    uint256 osMaxOrderDuration;
    uint256 zoraMinAuctionDuration;
    uint256 zoraMaxAuctionDuration;
    uint256 zoraMaxAuctionTimeout;
    address partyDaoMultisig;
    uint256 partyDaoDistributionSplitBps;
    address zoraAuctionHouseAddress;
    address osZone;
    bytes32 osConduitKey;
    address osConduitController;
    address fractionalVaultFactory;
    string networkName;
  }

  function rinkeby() internal pure returns (DeployConstants memory) {
    DeployConstants memory rinkebyDeployConstants = DeployConstants({
      adminAddresses: [
        0x8fDC86689f5F35F2b4d9f649c7bdc9C64f59e6bD,
        0x66512B61F855478bfba669e32719dE5fD7a57Fa4,
        0x678e8bd1D8845399c8e3C1F946CB4309014456a5,
        0xcAAAE655D431bdDB3F2f20bd31BC629928131582,
        0xc424f13e0aC6c0D5C1ED43e73A5771a2356e898d
      ],
      seaportExchangeAddress: 0x00000000006c3852cbEf3e08E8dF289169EdE581,
      osZoraAuctionDuration: 2 minutes,
      osZoraAuctionTimeout: 2 minutes,
      osMinOrderDuration: 2 minutes,
      osMaxOrderDuration: 14 days,
      zoraMinAuctionDuration: 2 minutes,
      zoraMaxAuctionDuration: 10 days,
      zoraMaxAuctionTimeout: 7 days,
      partyDaoMultisig: 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f,
      partyDaoDistributionSplitBps: PARTY_DAO_DISTRIBUTION_SPLIT_BPS,
      zoraAuctionHouseAddress: 0xE7dd1252f50B3d845590Da0c5eADd985049a03ce,
      osZone: 0x0000000000000000000000000000000000000000,
      osConduitKey: 0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000,
      osConduitController: 0x00000000F9490004C11Cef243f5400493c00Ad63,
      fractionalVaultFactory: 0x09EB641BA93CfA6340E944a22bDd2F1C8c745A9f,
      networkName: 'rinkeby'
    });

    return rinkebyDeployConstants;
  }

  function goerli() internal pure returns (DeployConstants memory) {
    DeployConstants memory rinkebyDeployConstants = DeployConstants({
      adminAddresses: [
        0x8fDC86689f5F35F2b4d9f649c7bdc9C64f59e6bD,
        0x66512B61F855478bfba669e32719dE5fD7a57Fa4,
        0x678e8bd1D8845399c8e3C1F946CB4309014456a5,
        0xcAAAE655D431bdDB3F2f20bd31BC629928131582,
        0xc424f13e0aC6c0D5C1ED43e73A5771a2356e898d
      ],
      seaportExchangeAddress: 0x00000000006c3852cbEf3e08E8dF289169EdE581,
      osZoraAuctionDuration: 2 minutes,
      osZoraAuctionTimeout: 2 minutes,
      osMinOrderDuration: 2 minutes,
      osMaxOrderDuration: 14 days,
      zoraMinAuctionDuration: 2 minutes,
      zoraMaxAuctionDuration: 10 days,
      zoraMaxAuctionTimeout: 7 days,
      partyDaoMultisig: 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f,
      partyDaoDistributionSplitBps: PARTY_DAO_DISTRIBUTION_SPLIT_BPS,
      zoraAuctionHouseAddress: 0x6a6Cdb103f1072E0aFeADAC9BeBD6E14B287Ca57,
      osZone: 0x00000000E88FE2628EbC5DA81d2b3CeaD633E89e,
      osConduitKey: 0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000,
      osConduitController: 0x00000000F9490004C11Cef243f5400493c00Ad63,
      networkName: 'goerli',
      fractionalVaultFactory: 0x014850E83d9D0D1BB0c8624035F09626b967B81c
    });

    return rinkebyDeployConstants;
  }
}
