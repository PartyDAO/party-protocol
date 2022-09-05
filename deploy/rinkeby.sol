// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import './deploy.sol';
import './LibDeployConstants.sol';

contract RinkebyDeploy is Deploy {
  function run() public {
    console.log('Starting rinkeby deploy script.');

    run(LibDeployConstants.rinkeby());

    console.log('Ending rinkeby deploy script.');
  }
}
