// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./Deploy.s.sol";
import "./LibDeployConstants.sol";

contract BaseDeploy is DeployScript {
    function _run() internal override {
        console.log("Starting base deploy script.");

        deploy(LibDeployConstants.base());

        console.log("Ending base deploy script.");
    }
}
