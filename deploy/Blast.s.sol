// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./blast/DeployBlast.s.sol";
import "./LibDeployConstants.sol";

contract BlastDeploy is DeployScriptBlast {
    function _run() internal override {
        console.log("Starting blast deploy script.");

        deploy(LibDeployConstants.blast(this.getDeployer()));

        console.log("Ending blast deploy script.");
    }
}
