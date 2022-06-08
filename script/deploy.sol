// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';

// import '../contracts/crowdfund/PartyCrowdfundFactory.sol';
import '../contracts/globals/Globals.sol';
import '../contracts/party/PartyFactory.sol';

contract Deploy is Test {

  // constants
  address partydaoMultisig = 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f;

  // temporary variables to store deployed contract addresses
  // PartyCrowdfundFactory partyCrowdfundFactoryAddress;
  PartyFactory partyFactoryAddress;
  Globals globals;

  function run() public {
    vm.startBroadcast();

    // DEPLOY_GLOBALS
    globals = new Globals(partydaoMultisig);

    // DEPLOY_PARTY_FACTORY
    partyFactoryAddress = new PartyFactory(globals);

    // DEPLOY_PARTY_CROWDFUND_FACTORY
    // partyCrowdfundFactoryAddress = new PartyCrowdfunFactory();

    vm.stopBroadcast();
  }
}
