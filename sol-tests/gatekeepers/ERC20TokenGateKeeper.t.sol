// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { Test } from "../../lib/forge-std/src/Test.sol";
import { console } from "../../lib/forge-std/src/console.sol";
import { DummyERC20 } from "../DummyERC20.sol";
import { TestUtils } from "../TestUtils.sol";
import { ERC20TokenGateKeeper } from "../../contracts/gatekeepers/ERC20TokenGateKeeper.sol";
import "../../contracts/utils/LibERC20Compat.sol";

contract ERC20TokenGateKeeperTest is Test, TestUtils {
    ERC20TokenGateKeeper gk;
    IERC20 immutable ETH_TOKEN = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    uint256 constant MIN_BALANCE = 5 ether;
    DummyERC20 dummyToken1 = new DummyERC20();



    function setUp() public {
        gk = new ERC20TokenGateKeeper();
    }

    function testUniqueGateIds() public {
        bytes12 gateId1 = gk.createGate(address(ETH_TOKEN), MIN_BALANCE);
        bytes12 gateId2 = gk.createGate(address(ETH_TOKEN), MIN_BALANCE);
        assertTrue(gateId1 != gateId2);
    }

    // should revert when token address is wrong
    // function testFailWrongTokenAddress() public {
    //     bytes12 gateId = gk.createGate(UNI_TOKEN, MIN_BALANCE);
    //     assertEq(gk.isAllowed(_randomAddress(), gateId, ""), false);
    // }

    //test assertion when the user doesn't have enough tokens
    function testInsufficentBalance() public {
        bytes12 gateId = gk.createGate(address(ETH_TOKEN), MIN_BALANCE);
        address user = _randomAddress();
        dummyToken1.deal(user, 4 ether);
        assertEq(gk.isAllowed(user, gateId, ""), false);
    }

   // test with sufficent balance
    function testSufficentBalance() public {
        bytes12 gateId = gk.createGate(address(ETH_TOKEN), MIN_BALANCE);
        address user = _randomAddress();
        dummyToken1.deal(user, 7 ether);
        assertEq(gk.isAllowed(user, gateId, ""), true);
    }

    // test separate gate access
    // function testSeparateGateAccess() public {
    //     bytes12 gateId1 = gk.createGate(ETH_TOKEN, MIN_BALANCE);
    //     // set a different token here
    //     bytes12 gateId2 = gk.createGate(ETH_TOKEN, MIN_BALANCE);
    //     // set two users with two different tokens
    //     //figure out how to set the correct address property to test accurately
    //     //assuming all of these addresses should be different
    //     assertEq(gk.isAllowed(memberAddress, gateId1, ""), true);
    //     assertEq(gk.isAllowed(memberAddress, gateId2, ""), true);
    //     assertEq(gk.isAllowed(memberAddress, gateId1, ""), false);
    //     assertEq(gk.isAllowed(memberAddress, gateId2, ""), false);
    // }
}
