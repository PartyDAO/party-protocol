// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';

import './deploy.sol';
import './LibDeployConstants.sol';

contract MainnetDeploy is Test {
  function run() public {
    console.log('Starting mainnet deploy script.');

    Deploy deploy = new Deploy();
    deploy.run(LibDeployConstants.mainnet());
    
    console.log('Ending mainnet deploy script.');
  }
}
