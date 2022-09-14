// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import './deploy.sol';
import './LibDeployConstants.sol';

contract RinkebyDeploy is DeployScript {
  function run() public {
    console.log('Starting rinkeby deploy script.');

    deploy(LibDeployConstants.rinkeby(this.getDeployer()));

    console.log('Ending rinkeby deploy script.');
  }
}
