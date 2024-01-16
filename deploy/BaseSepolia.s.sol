// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./Deploy.s.sol";
import "./LibDeployConstants.sol";

contract SepoliaDeploy is DeployScript {
    function _run() internal override {
        console.log("Starting base sepolia deploy script.");

        deploy(LibDeployConstants.baseSepolia(this.getDeployer()));

        console.log("Ending base sepolia deploy script.");
    }
}
