// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./Deploy.s.sol";
import "./LibDeployConstants.sol";

contract MainnetDeploy is DeployScript {
    function _run() internal override {
        console.log("Starting mainnet deploy script.");

        deploy(LibDeployConstants.mainnet());

        console.log("Ending mainnet deploy script.");
    }
}
