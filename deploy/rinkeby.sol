// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';

import './deploy.sol';
import './LibDeployConstants.sol';

contract RinkebyDeploy is Test {
  function run() public {
    console.log('Starting rinkeby deploy script.');

    Deploy deploy = new Deploy();
    deploy.run(LibDeployConstants.rinkeby());
    
    console.log('Ending rinkeby deploy script.');
  }
}
