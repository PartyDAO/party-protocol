// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./blast/DeployBlast.s.sol";
import "./LibDeployConstants.sol";

contract BlastSepoliaDeploy is DeployScriptBlast {
    function _run() internal override {
        console.log("Starting blast sepolia deploy script.");

        deploy(LibDeployConstants.blastSepolia(this.getDeployer()));

        console.log("Ending blast sepolia deploy script.");
    }
}
