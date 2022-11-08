// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import './deploy.sol';
import './LibDeployConstants.sol';

contract MainnetDeploy is DeployScript {
  function _run() internal override {
    console.log('Starting mainnet deploy script.');

    deploy(LibDeployConstants.mainnet());

    console.log('Ending mainnet deploy script.');
  }

  function _useVanityDeployer(address deployer) internal override {
    vm.broadcast(deployer);
  }
}
