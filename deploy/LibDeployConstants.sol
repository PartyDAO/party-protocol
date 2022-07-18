// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

// TODO: verify these constants

library LibDeployConstants {
  uint256 internal constant PARTY_DAO_DISTRIBUTION_SPLIT_BPS = 250;
  // todo: use for mainnet deploy
  // uint256 internal constant OS_ZORA_AUCTION_DURATION = 86400; // 60 * 60 * 24 = 86400 seconds = 24 hours
  uint256 internal constant OS_ZORA_AUCTION_DURATION = 2 minutes;

  struct DeployConstants {
    address[3] adminAddresses; // todo: change size of array based on deploy
    address seaportExchangeAddress;
    uint256 osZoraAuctionDuration;
    uint256 osZoraAuctionTimeout;
    address partyDaoMultisig;
    uint256 partyDaoDistributionSplitBps;
    address zoraAuctionHouseAddress;
    address osZone;
    bytes32 osConduitKey;
    address osConduitController;
  }

  function mainnet() internal pure returns (DeployConstants memory) {
    DeployConstants memory mainnetDeployConstants = DeployConstants({
      adminAddresses: [
        0x0000000000000000000000000000000000000000,
        0x000000000000000000000000000000000000dEaD,
        0x0000000000000000000000000000000000001337
      ],
      seaportExchangeAddress: 0x00000000006c3852cbEf3e08E8dF289169EdE581,
      osZoraAuctionDuration: OS_ZORA_AUCTION_DURATION,
      partyDaoMultisig: 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f,
      partyDaoDistributionSplitBps: PARTY_DAO_DISTRIBUTION_SPLIT_BPS,
      zoraAuctionHouseAddress: 0xE468cE99444174Bd3bBBEd09209577d25D1ad673,
      osZoraAuctionTimeout: 24 hours,
      osZone: address(0), // TODO,
      osConduitKey: 0, // TODO
      osConduitController: address(0) // TODO
    });

    return mainnetDeployConstants;
  }

  function rinkeby() internal pure returns (DeployConstants memory) {
    DeployConstants memory rinkebyDeployConstants = DeployConstants({
      adminAddresses: [
        0x8fDC86689f5F35F2b4d9f649c7bdc9C64f59e6bD,
        0x66512B61F855478bfba669e32719dE5fD7a57Fa4,
        0x678e8bd1D8845399c8e3C1F946CB4309014456a5
      ],
      seaportExchangeAddress: 0x00000000006c3852cbEf3e08E8dF289169EdE581,
      osZoraAuctionDuration: 2 minutes,
      osZoraAuctionTimeout: 2 minutes,
      partyDaoMultisig: 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f,
      partyDaoDistributionSplitBps: PARTY_DAO_DISTRIBUTION_SPLIT_BPS,
      zoraAuctionHouseAddress: 0xE7dd1252f50B3d845590Da0c5eADd985049a03ce,
      osZone: 0x00000000E88FE2628EbC5DA81d2b3CeaD633E89e,
      osConduitKey: 0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000,
      osConduitController: 0x00000000F9490004C11Cef243f5400493c00Ad63
    });

    return rinkebyDeployConstants;
  }
}
