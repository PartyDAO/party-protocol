// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./Deploy.s.sol";
import "./LibDeployConstants.sol";

contract BaseGoerliDeploy is DeployScript {
    function _run() internal override {
        console.log("Starting base goerli deploy script.");

        deploy(LibDeployConstants.baseGoerli(this.getDeployer()));

        console.log("Ending base goerli deploy script.");
    }
}
