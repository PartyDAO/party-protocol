// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import './deploy.sol';
import './LibDeployConstants.sol';

contract MainnetDeploy is DeployScript {
  function run() public {
    console.log('Starting mainnet deploy script.');

    deploy(LibDeployConstants.mainnet());

    console.log('Ending mainnet deploy script.');
  }
}
