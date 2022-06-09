// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {DummyERC20} from "../DummyERC20.sol";
import {TestUtils} from "../TestUtils.sol";
import {ERC20TokenGateKeeper} from "../../contracts/gatekeepers/ERC20TokenGateKeeper.sol";
import "../../contracts/utils/LibERC20Compat.sol";

contract ERC20TokenGateKeeperTest is Test, TestUtils {
    ERC20TokenGateKeeper gk;
    uint256 constant MIN_BALANCE = 5e24;
    DummyERC20 dummyToken1 = new DummyERC20();
    DummyERC20 dummyToken2 = new DummyERC20();

    function setUp() public {
        gk = new ERC20TokenGateKeeper();
    }

    function testUniqueGateIds() public {
        bytes12 gateId1 = gk.createGate(dummyToken1, MIN_BALANCE);
        bytes12 gateId2 = gk.createGate(dummyToken1, MIN_BALANCE);
        assertTrue(gateId1 != gateId2);
    }

    function testDifferentMinimumBalance() public {
        uint256 min_balance = 7e24;
        bytes12 gateId = gk.createGate(dummyToken1, min_balance);
        address user = _randomAddress();
        dummyToken1.deal(user, 8e24);
        assertEq(gk.isAllowed(user, gateId, ""), true);
    }

    function testEqualToMinimumBalance() public {
        bytes12 gateId = gk.createGate(dummyToken1, MIN_BALANCE);
        address user = _randomAddress();
        dummyToken1.deal(user, 5e24);
        assertEq(gk.isAllowed(user, gateId, ""), true);
    }

    function testInsufficentBalance() public {
        bytes12 gateId = gk.createGate(dummyToken1, MIN_BALANCE);
        address user = _randomAddress();
        dummyToken1.deal(user, 4e24);
        assertEq(gk.isAllowed(user, gateId, ""), false);
    }

    function testSufficentBalance() public {
        bytes12 gateId = gk.createGate(dummyToken1, MIN_BALANCE);
        address user = _randomAddress();
        dummyToken1.deal(user, 7e24);
        assertEq(gk.isAllowed(user, gateId, ""), true);
    }

    function testSeparateGateAccess() public {
        bytes12 gateId1 = gk.createGate(dummyToken1, MIN_BALANCE);
        bytes12 gateId2 = gk.createGate(dummyToken2, MIN_BALANCE);
        address user1 = _randomAddress();
        address user2 = _randomAddress();
        dummyToken1.deal(user1, 6e24);
        dummyToken2.deal(user2, 7e24);
        assertEq(gk.isAllowed(user1, gateId1, ""), true);
        assertEq(gk.isAllowed(user2, gateId2, ""), true);
        assertEq(gk.isAllowed(user1, gateId2, ""), false);
        assertEq(gk.isAllowed(user2, gateId1, ""), false);
    }
}
