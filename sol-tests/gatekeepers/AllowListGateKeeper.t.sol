// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/gatekeepers/AllowListGateKeeper.sol";
import "../TestUtils.sol";

contract AllowListGateKeeperTest is Test, TestUtils {
    AllowListGateKeeper gk;

    function setUp() public {
        gk = new AllowListGateKeeper();
    }

    function testUniqueGateIds() public {
        bytes12 gateId1 = gk.createGate(new address[](0));
        bytes12 gateId2 = gk.createGate(new address[](0));
        assertTrue(gateId1 != gateId2);
    }

    function testEmptyGate() public {
        bytes12 gateId = gk.createGate(new address[](0));
        assertEq(gk.isAllowed(_randomAddress(), gateId, ""), false);
    }

    function testSingleMemberGatePositive() public {
        address[]  memory members = new address[](1);
        members[0] = _randomAddress();
        bytes12 gateId = gk.createGate(members);
        assertEq(gk.isAllowed(members[0], gateId, ""), true);
    }

    function testSingleMemberGateNegative() public {
        address[]  memory members = new address[](1);
        members[0] = _randomAddress();
        bytes12 gateId = gk.createGate(members);
        assertEq(gk.isAllowed(_randomAddress(), gateId, ""), false);
    }

    function testMultiMemberGatePositive() public {
        address[]  memory members = new address[](2);
        members[0] = _randomAddress();
        members[1] = _randomAddress();
        bytes12 gateId = gk.createGate(members);
        assertEq(gk.isAllowed(members[0], gateId, ""), true);
        assertEq(gk.isAllowed(members[1], gateId, ""), true);
    }

    function testMultiMemberGateNegative() public {
        address[]  memory members = new address[](2);
        members[0] = _randomAddress();
        members[1] = _randomAddress();
        bytes12 gateId = gk.createGate(members);
        assertEq(gk.isAllowed(_randomAddress(), gateId, ""), false);
    }

    function testSeparateGates() public {
        address[]  memory members1 = new address[](1);
        address[]  memory members2 = new address[](1);
        members1[0] = _randomAddress();
        members2[0] = _randomAddress();
        bytes12 gateId1 = gk.createGate(members1);
        bytes12 gateId2 = gk.createGate(members2);
        assertEq(gk.isAllowed(members1[0], gateId1, ""), true);
        assertEq(gk.isAllowed(members2[0], gateId2, ""), true);
        assertEq(gk.isAllowed(members2[0], gateId1, ""), false);
        assertEq(gk.isAllowed(members1[0], gateId2, ""), false);
    }
}
