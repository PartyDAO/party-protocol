// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { Test } from "../../lib/forge-std/src/Test.sol";
import { console } from "../../lib/forge-std/src/console.sol";
import { TestUtils } from "../TestUtils.sol";
import { ContributionRangeGateKeeper } from "../../contracts/gatekeepers/ContributionRangeGateKeeper.sol";

contract ContributionRangeGateKeeperTest is Test, TestUtils {
    ContributionRangeGateKeeper gk;

    function setUp() public {
        gk = new ContributionRangeGateKeeper();
    }

    function testUniqueGateIds() public {
        bytes12 gateId1 = gk.createGate(0, 0);
        bytes12 gateId2 = gk.createGate(0, 0);
        assertTrue(gateId1 != gateId2);
    }

    function testAboveMinimumRange() public {
        uint96 min = 10;
        uint96 max = 100;
        bytes12 gateId = gk.createGate(min, max);
        address user = _randomAddress();
        assertTrue(gk.isAllowed(user, min + 1, gateId, ""));
    }

    function testEqualToMinimumRange() public {
        uint96 min = 10;
        uint96 max = 100;
        bytes12 gateId = gk.createGate(min, max);
        address user = _randomAddress();
        assertTrue(gk.isAllowed(user, min, gateId, ""));
    }

    function testBelowMinimumRange() public {
        uint96 min = 10;
        uint96 max = 100;
        bytes12 gateId = gk.createGate(min, max);
        address user = _randomAddress();
        assertFalse(gk.isAllowed(user, min - 1, gateId, ""));
    }

    function testAboveMaximumRange() public {
        uint96 min = 10;
        uint96 max = 100;
        bytes12 gateId = gk.createGate(min, max);
        address user = _randomAddress();
        assertFalse(gk.isAllowed(user, max + 1, gateId, ""));
    }

    function testEqualToMaximumRange() public {
        uint96 min = 10;
        uint96 max = 100;
        bytes12 gateId = gk.createGate(min, max);
        address user = _randomAddress();
        assertTrue(gk.isAllowed(user, max, gateId, ""));
    }

    function testBelowMaximumRange() public {
        uint96 min = 10;
        uint96 max = 100;
        bytes12 gateId = gk.createGate(min, max);
        address user = _randomAddress();
        assertTrue(gk.isAllowed(user, max - 1, gateId, ""));
    }

    function testMinMaxEqual() public {
        uint96 increment = 100;
        bytes12 gateId = gk.createGate(increment, increment);
        address user = _randomAddress();
        assertTrue(gk.isAllowed(user, increment, gateId, ""));
        assertFalse(gk.isAllowed(user, increment - 1, gateId, ""));
        assertFalse(gk.isAllowed(user, increment + 1, gateId, ""));
    }

    function testMinGreaterThanMax() public {
        uint96 min = 100;
        uint96 max = 10;
        vm.expectRevert(
            abi.encodeWithSelector(
                ContributionRangeGateKeeper.MinGreaterThanMaxError.selector,
                min,
                max
            )
        );
        gk.createGate(min, max);
    }
}
