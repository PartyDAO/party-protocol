// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./Deploy.s.sol";
import "./LibDeployConstants.sol";

contract GoerliDeploy is DeployScript {
    function _run() internal override {
        console.log("Starting goerli deploy script.");

        deploy(LibDeployConstants.goerli(this.getDeployer()));

        console.log("Ending goerli deploy script.");
    }
}
