// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {DummyERC721} from "../DummyERC721.sol";
import {TestUtils} from "../TestUtils.sol";
import {ERC721TokenGateKeeper} from "../../contracts/gatekeepers/ERC721TokenGateKeeper.sol";

contract ERC721TokenGateKeeperTest is Test, TestUtils {
    ERC721TokenGateKeeper gk;
    DummyERC721 dummyToken1 = new DummyERC721();
    DummyERC721 dummyToken2 = new DummyERC721();

    function setUp() public {
        gk = new ERC721TokenGateKeeper();
    }

    function testUniqueGateIds() public {
        bytes12 gateId1 = gk.createGate(dummyToken1, 1);
        bytes12 gateId2 = gk.createGate(dummyToken1, 1);
        assertTrue(gateId1 != gateId2);
    }

    function testEqualToMinimumBalance() public {
        bytes12 gateId = gk.createGate(dummyToken1, 2);
        address user = _randomAddress();
        dummyToken1.mint(user);
        dummyToken1.mint(user);
        assertEq(gk.isAllowed(user, gateId, ""), true);
    }

    function testAboveMinimumBalance() public {
        bytes12 gateId = gk.createGate(dummyToken1, 1);
        address user = _randomAddress();
        dummyToken1.mint(user);
        dummyToken1.mint(user);
        assertEq(gk.isAllowed(user, gateId, ""), true);
    }

    function testInsufficientBalance() public {
        bytes12 gateId = gk.createGate(dummyToken1, 1);
        address user = _randomAddress();
        assertEq(gk.isAllowed(user, gateId, ""), false);
    }

    function testSeparateGateAccess() public {
        bytes12 gateId1 = gk.createGate(dummyToken1, 1);
        bytes12 gateId2 = gk.createGate(dummyToken2, 1);
        address user1 = _randomAddress();
        address user2 = _randomAddress();
        dummyToken1.mint(user1);
        dummyToken2.mint(user2);
        assertEq(gk.isAllowed(user1, gateId1, ""), true);
        assertEq(gk.isAllowed(user2, gateId2, ""), true);
        assertEq(gk.isAllowed(user1, gateId2, ""), false);
        assertEq(gk.isAllowed(user2, gateId1, ""), false);
    }
}
