// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { Test } from "../../lib/forge-std/src/Test.sol";
import { console } from "../../lib/forge-std/src/console.sol";
import { TestUtils } from "../TestUtils.sol";
import { ContributionLimitGateKeeper } from "../../contracts/gatekeepers/ContributionLimitGateKeeper.sol";

contract ContributionLimitGateKeeperTest is Test, TestUtils {
    ContributionLimitGateKeeper gk;
    DummyCrowdfund cf;

    function setUp() public {
        gk = new ContributionLimitGateKeeper();
        cf = new DummyCrowdfund();
    }

    function testUniqueGateIds() public {
        bytes12 gateId1 = gk.createGate(0, 0);
        bytes12 gateId2 = gk.createGate(0, 0);
        assertTrue(gateId1 != gateId2);
    }

    function testAboveMinimumLimit() public {
        uint96 min = 10;
        uint96 max = 100;
        bytes12 gateId = gk.createGate(min, max);
        address user = _randomAddress();
        cf.setContributed(user, min + 1);
        vm.prank(address(cf));
        assertTrue(gk.isAllowed(user, 0, gateId, ""));
    }

    function testEqualToMinimumLimit() public {
        uint96 min = 10;
        uint96 max = 100;
        bytes12 gateId = gk.createGate(min, max);
        address user = _randomAddress();
        cf.setContributed(user, min);
        vm.prank(address(cf));
        assertTrue(gk.isAllowed(user, 0, gateId, ""));
    }

    function testBelowMinimumLimit() public {
        uint96 min = 10;
        uint96 max = 100;
        bytes12 gateId = gk.createGate(min, max);
        address user = _randomAddress();
        cf.setContributed(user, min - 1);
        vm.prank(address(cf));
        assertFalse(gk.isAllowed(user, 0, gateId, ""));
    }

    function testAboveMaximumLimit() public {
        uint96 min = 10;
        uint96 max = 100;
        bytes12 gateId = gk.createGate(min, max);
        address user = _randomAddress();
        cf.setContributed(user, max + 1);
        vm.prank(address(cf));
        assertFalse(gk.isAllowed(user, 0, gateId, ""));
    }

    function testEqualToMaximumLimit() public {
        uint96 min = 10;
        uint96 max = 100;
        bytes12 gateId = gk.createGate(min, max);
        address user = _randomAddress();
        cf.setContributed(user, max);
        vm.prank(address(cf));
        assertTrue(gk.isAllowed(user, 0, gateId, ""));
    }

    function testBelowMaximumLimit() public {
        uint96 min = 10;
        uint96 max = 100;
        bytes12 gateId = gk.createGate(min, max);
        address user = _randomAddress();
        cf.setContributed(user, max - 1);
        vm.prank(address(cf));
        assertTrue(gk.isAllowed(user, 0, gateId, ""));
    }

    function testMinMaxEqual() public {
        uint96 increment = 100;
        bytes12 gateId = gk.createGate(increment, increment);
        address user = _randomAddress();
        cf.setContributed(user, increment);
        vm.prank(address(cf));
        assertTrue(gk.isAllowed(user, 0, gateId, ""));
        cf.setContributed(user, increment + 1);
        vm.prank(address(cf));
        assertFalse(gk.isAllowed(user, 0, gateId, ""));
        cf.setContributed(user, increment - 1);
        vm.prank(address(cf));
        assertFalse(gk.isAllowed(user, 0, gateId, ""));
    }

    function testMinGreaterThanMax() public {
        uint96 min = 100;
        uint96 max = 10;
        vm.expectRevert(
            abi.encodeWithSelector(
                ContributionLimitGateKeeper.MinGreaterThanMaxError.selector,
                min,
                max
            )
        );
        gk.createGate(min, max);
    }
}

contract DummyCrowdfund {
    mapping(address => uint256) public totalContributed;

    function setContributed(address participant, uint256 amount) external {
        totalContributed[participant] = amount;
    }

    function getContributorInfo(
        address participant
    ) external view returns (uint256 ethContributed, uint256, uint256, uint256) {
        return (totalContributed[participant], 0, 0, 0);
    }
}
