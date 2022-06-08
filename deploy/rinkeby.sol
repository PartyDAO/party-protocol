// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';

import './deploy.sol';
import './LibDeployAddresses.sol';

contract RinkebyDeploy is Test {
  function run() public {
    console.log('Starting rinkeby deploy script.');

    Deploy deploy = new Deploy();
    deploy.run(LibDeployAddresses.rinkeby());
    
    console.log('Ending rinkeby deploy script.');
  }
}
