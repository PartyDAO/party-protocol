// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import './deploy.sol';
import './LibDeployConstants.sol';

contract MainnetDeploy is Deploy {
  function run() public {
    console.log('Starting mainnet deploy script.');

    run(LibDeployConstants.mainnet());

    console.log('Ending mainnet deploy script.');
  }
}
