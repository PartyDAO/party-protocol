// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';

import '../contracts/crowdfund/PartyCrowdfunFactory.sol';
import '../contracts/globals/Globals.sol';

contract Deploy is Test {

  // constants
  address partydaoMultisig = 0xf7f52dd34bc21eda08c0b804c7c1dbc48375820f;

  // temporary variables to store deployed contract addresses
  PartyCrowdfundFactory partyCrowdfundFactoryAddress;
  Globals globalsAddress;

  function run() public {
    vm.startBroadcast();

    // DEPLOY_GLOBALS
    globals = new Globals(partydaoMultisig);

    // DEPLOY_V3_CORE_FACTORY
    partyCrowdfundFactoryAddress = new PartyCrowdfunFactory();

    vm.stopBroadcast();
  }
}
