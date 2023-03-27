// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./Deploy.s.sol";
import "./LibDeployConstants.sol";

contract MainnetDeploy is DeployScript {
    constructor() {
        _deployerByRole[DeployerRole.Default] = 0xdf6602CB4175618228259614fe3792b51919eDdf;
        _deployerByRole[DeployerRole.PartyFactory] = 0x5084EAC7494814249E57882722d51bD0eFcA1459;
        _deployerByRole[DeployerRole.CrowdfundFactory] = 0x6b244BAe54866c05c85F072D10567d1A964a21aF;
        _deployerByRole[DeployerRole.TokenDistributor] = 0xB232F14e8061E2456E325B75C3f7946F3bc382CF;
    }

    function _run() internal override {
        console.log("Starting mainnet deploy script.");

        deploy(LibDeployConstants.mainnet());

        console.log("Ending mainnet deploy script.");
    }
}
