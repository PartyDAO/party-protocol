// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./Deploy.s.sol";
import "./LibDeployConstants.sol";

contract ZoraDeploy is DeployScript {
    function _run() internal override {
        console.log("Starting zora deploy script.");

        deploy(LibDeployConstants.zora());

        console.log("Ending zora deploy script.");
    }
}
