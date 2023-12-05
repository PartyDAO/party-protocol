// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { Test } from "../../lib/forge-std/src/Test.sol";
import { console } from "../../lib/forge-std/src/console.sol";
import { DummyERC20 } from "../DummyERC20.sol";
import { DummyERC721 } from "../DummyERC721.sol";
import { DummyERC1155 } from "../DummyERC1155.sol";
import { TestUtils } from "../TestUtils.sol";
import { TokenGateKeeper } from "../../contracts/gatekeepers/TokenGateKeeper.sol";
import "../../contracts/utils/LibERC20Compat.sol";

contract TokenGateKeeperTest is Test, TestUtils {
    TokenGateKeeper gk;
    uint256 constant MIN_ERC20_BALANCE = 10e18;
    uint256 constant MIN_ERC721_BALANCE = 1;
    uint256 constant MIN_ERC1155_BALANCE = 1;
    DummyERC20 dummyERC20 = new DummyERC20();
    DummyERC721 dummyERC721 = new DummyERC721();
    DummyERC1155 dummyERC1155 = new DummyERC1155();

    function setUp() public {
        gk = new TokenGateKeeper(address(0));
    }

    function testUniqueGateIds() public {
        bytes12 gateId1 = gk.createGate(address(dummyERC20), MIN_ERC20_BALANCE);
        bytes12 gateId2 = gk.createGate(address(dummyERC721), MIN_ERC721_BALANCE);
        assertTrue(gateId1 != gateId2);
    }

    function testAboveMinimumBalance() public {
        bytes12 ERC20gateId = gk.createGate(address(dummyERC20), MIN_ERC20_BALANCE);
        bytes12 ERC721gateId = gk.createGate(address(dummyERC721), MIN_ERC721_BALANCE);
        address user = _randomAddress();
        dummyERC20.deal(user, MIN_ERC20_BALANCE + 1);
        dummyERC721.mint(user);
        dummyERC721.mint(user);
        assertTrue(gk.isAllowed(user, ERC20gateId, ""));
        assertTrue(gk.isAllowed(user, ERC721gateId, ""));
    }

    function testEqualToMinimumBalance() public {
        bytes12 ERC20gateId = gk.createGate(address(dummyERC20), MIN_ERC20_BALANCE);
        bytes12 ERC721gateId = gk.createGate(address(dummyERC721), MIN_ERC721_BALANCE);
        address user = _randomAddress();
        dummyERC20.deal(user, MIN_ERC20_BALANCE);
        dummyERC721.mint(user);
        assertTrue(gk.isAllowed(user, ERC20gateId, ""));
        assertTrue(gk.isAllowed(user, ERC721gateId, ""));
    }

    function testBelowMinimumBalance() public {
        bytes12 ERC20gateId = gk.createGate(address(dummyERC20), MIN_ERC20_BALANCE);
        bytes12 ERC721gateId = gk.createGate(address(dummyERC721), MIN_ERC721_BALANCE);
        address user = _randomAddress();
        assertFalse(gk.isAllowed(user, ERC20gateId, ""));
        assertFalse(gk.isAllowed(user, ERC721gateId, ""));
    }

    function testSeparateGateAccess() public {
        bytes12 ERC20gateId = gk.createGate(address(dummyERC20), MIN_ERC20_BALANCE);
        bytes12 ERC721gateId = gk.createGate(address(dummyERC721), MIN_ERC721_BALANCE);
        address user1 = _randomAddress();
        address user2 = _randomAddress();
        dummyERC20.deal(user1, MIN_ERC20_BALANCE);
        dummyERC721.mint(user2);
        assertTrue(gk.isAllowed(user1, ERC20gateId, ""));
        assertTrue(gk.isAllowed(user2, ERC721gateId, ""));
        assertFalse(gk.isAllowed(user1, ERC721gateId, ""));
        assertFalse(gk.isAllowed(user2, ERC20gateId, ""));
    }

    function test1155Gate() public {
        bytes12 ERC1155gateId = gk.createGate(address(dummyERC1155), 1, MIN_ERC1155_BALANCE);
        address user = _randomAddress();
        dummyERC1155.deal(user, 1, 1);
        assertTrue(gk.isAllowed(user, ERC1155gateId, ""));
    }

    function test1155Gate_wrongId() public {
        bytes12 ERC1155gateId = gk.createGate(address(dummyERC1155), 1, MIN_ERC1155_BALANCE);
        address user = _randomAddress();
        dummyERC1155.deal(user, 2, 1);
        assertFalse(gk.isAllowed(user, ERC1155gateId, ""));
    }

    function test1155Gate_notEnough() public {
        bytes12 ERC1155gateId = gk.createGate(address(dummyERC1155), 1, 3);
        address user = _randomAddress();
        dummyERC1155.deal(user, 1, 2);
        assertFalse(gk.isAllowed(user, ERC1155gateId, ""));
    }
}
