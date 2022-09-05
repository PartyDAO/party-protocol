// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import './deploy.sol';
import './LibDeployConstants.sol';

contract GoerliDeploy is Deploy {
  function run() public {
    console.log('Starting goerli deploy script.');

    run(LibDeployConstants.goerli());

    console.log('Ending goerli deploy script.');
  }
}
