// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';

// import '../contracts/crowdfund/PartyCrowdfundFactory.sol';
import '../contracts/distribution/TokenDistributor.sol';
import '../contracts/globals/Globals.sol';
import '../contracts/party/PartyFactory.sol';

contract Deploy is Test {

  // constants
  address partydaoMultisig = 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f;

  // temporary variables to store deployed contract addresses
  // PartyCrowdfundFactory partyCrowdfundFactoryAddress;
  PartyFactory partyFactoryAddress;
  TokenDistributor tokenDistributorAddress;
  Globals globals;

  function run() public {
    console.log('Starting deploy script.');
    vm.startBroadcast();

    // DEPLOY_GLOBALS
    console.log('Deploying - Globals');
    globals = new Globals(partydaoMultisig);
    console.log('Deployed - Globals', address(globals));

    // DEPLOY_PARTY_FACTORY
    console.log('Deploying - PartyFactory');
    partyFactoryAddress = new PartyFactory(globals);
    console.log('Deployed - PartyFactory', address(partyFactoryAddress));

    // DEPLOY_TOKEN_DISTRIBUTOR
    console.log('Deploying - TokenDistributor');
    tokenDistributorAddress = new TokenDistributor(globals);
    console.log('Deployed - TokenDistributor', address(tokenDistributorAddress));

    // DEPLOY_PARTY_CROWDFUND_FACTORY
    // console.log('Deploying - PartyCrowdfunFactory');
    // partyCrowdfundFactoryAddress = new PartyCrowdfunFactory();
    // console.log('Deployed - PartyCrowdfunFactory', address(partyCrowdfundFactoryAddress));

    vm.stopBroadcast();
    console.log('Ending deploy script.');
  }
}
