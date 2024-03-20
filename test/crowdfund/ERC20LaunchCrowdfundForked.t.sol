// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";

contract ERC20LaunchCrowdfundForkedTest is SetupPartyHelper {
    constructor() onlyForked SetupPartyHelper(true) {}

    function test_ERC20LaunchCrowdfund_happy_path() public onlyForked {
        // Deploy the ERC20 token
    }
}
