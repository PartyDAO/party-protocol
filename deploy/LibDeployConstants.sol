// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

// TODO: verify these constants

library LibDeployConstants {
  uint256 internal constant PARTY_DAO_DISTRIBUTION_SPLIT_BPS = 250;
  uint256 internal constant OS_ZORA_AUCTION_DURATION = 86400; // 60 * 60 * 24 = 86400 seconds = 24 hours

  struct DeployConstants {
    address[3] adminAddresses; // todo: change size of array based on deploy
    address openSeaExchangeAddress;
    uint256 osZoraAuctionDuration;
    address partyDaoMultisig;
    uint256 partyDaoDistributionSplitBps;
    address zoraAuctionHouseAddress;
  }

  function mainnet() internal pure returns (DeployConstants memory) {
    DeployConstants memory mainnetDeployConstants = DeployConstants({
      adminAddresses: [
        0x0000000000000000000000000000000000000000,
        0x000000000000000000000000000000000000dEaD,
        0x0000000000000000000000000000000000001337
      ],
      openSeaExchangeAddress: 0x7f268357A8c2552623316e2562D90e642bB538E5,
      osZoraAuctionDuration: OS_ZORA_AUCTION_DURATION,
      partyDaoMultisig: 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f,
      partyDaoDistributionSplitBps: PARTY_DAO_DISTRIBUTION_SPLIT_BPS,
      zoraAuctionHouseAddress: 0xE468cE99444174Bd3bBBEd09209577d25D1ad673
    });

    return mainnetDeployConstants;
  }

  function rinkeby() internal pure returns (DeployConstants memory) {
    DeployConstants memory rinkebyDeployConstants = DeployConstants({
      adminAddresses: [
        0x0000000000000000000000000000000000000000,
        0x000000000000000000000000000000000000dEaD,
        0x0000000000000000000000000000000000001337
      ],
      openSeaExchangeAddress: 0xdD54D660178B28f6033a953b0E55073cFA7e3744,
      osZoraAuctionDuration: OS_ZORA_AUCTION_DURATION,
      partyDaoMultisig: 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f,
      partyDaoDistributionSplitBps: PARTY_DAO_DISTRIBUTION_SPLIT_BPS,
      zoraAuctionHouseAddress: 0xE7dd1252f50B3d845590Da0c5eADd985049a03ce
    });

    return rinkebyDeployConstants;
  }
}
