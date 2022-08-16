// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';

import './deploy.sol';
import './LibDeployConstants.sol';

contract GoerliDeploy is Test {
  function run() public {
    console.log('Starting goerli deploy script.');

    Deploy deploy = new Deploy();
    deploy.run(LibDeployConstants.goerli());

    console.log('Ending goerli deploy script.');
  }
}
