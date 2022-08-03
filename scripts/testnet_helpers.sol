// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';
import "../contracts/utils/TestnetHelpers.sol";

contract TestnetHelpersDeploy is Test {
  function run() public {
    vm.startBroadcast();
    TestnetHelpers tn = new TestnetHelpers();
    console.log("Deployed to:");
    console.log(address(tn));
    vm.stopBroadcast();
  }
}
