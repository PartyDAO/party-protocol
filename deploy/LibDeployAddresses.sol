// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

// TODO: verify these constants

library LibDeployAddresses {
  struct DeployAddresses {
    address adminAddress;
    address openSeaExchangeAddress;
    address partyDaoMultisig;
    address zoraAuctionHouseAddress;
  }

  function mainnet() public pure returns (DeployAddresses memory) {
    DeployAddresses memory mainnetDeployAddresses = DeployAddresses({
      adminAddress: 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f,
      openSeaExchangeAddress: 0x7f268357A8c2552623316e2562D90e642bB538E5,
      partyDaoMultisig: 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f,
      zoraAuctionHouseAddress: 0xE468cE99444174Bd3bBBEd09209577d25D1ad673
    });

    return mainnetDeployAddresses;
  }

  function rinkeby() public pure returns (DeployAddresses memory) {
    DeployAddresses memory rinkebyDeployAddresses = DeployAddresses({
      adminAddress: 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f,
      openSeaExchangeAddress: 0xdD54D660178B28f6033a953b0E55073cFA7e3744,
      partyDaoMultisig: 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f,
      zoraAuctionHouseAddress: 0xE7dd1252f50B3d845590Da0c5eADd985049a03ce
    });

    return rinkebyDeployAddresses;
  }
}
