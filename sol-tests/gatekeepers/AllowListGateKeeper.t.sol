// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/gatekeepers/AllowListGateKeeper.sol";
import "../TestUtils.sol";

contract AllowListGateKeeperTest is Test, TestUtils {
    AllowListGateKeeper gk = new AllowListGateKeeper();

    // Generates a randomized 4-member allow list.
    function _randomAllowList() private view returns (address[4] memory allowList) {
        for (uint i = 0; i < 4; ++i) {
            allowList[i] = _randomAddress();
        }
    }

    // Constructs a merkle root from the given 4-member allow list.
    function _constructTree(address[4] memory members) private pure returns (bytes32 merkleRoot) {
        merkleRoot = _hashNode(
            _hashNode(_hashLeaf(members[0]), _hashLeaf(members[1])),
            _hashNode(_hashLeaf(members[2]), _hashLeaf(members[3]))
        );
    }

    function _hashNode(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return keccak256(a < b ? abi.encodePacked(a, b) : abi.encodePacked(b, a));
    }

    function _hashLeaf(address a) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(a));
    }

    function testUniqueGateIds() public {
        bytes12 gateId1 = gk.createGate(_constructTree(_randomAllowList()));
        bytes12 gateId2 = gk.createGate(_constructTree(_randomAllowList()));
        assertTrue(gateId1 != gateId2);
    }

    function testSingleMemberGatePositive() public {
        address member = _randomAddress();
        bytes12 gateId = gk.createGate(_hashLeaf(member));
        assertTrue(gk.isAllowed(member, gateId, abi.encode(new bytes32[](0))));
    }

    function testSingleMemberGateNegative() public {
        address member = _randomAddress();
        bytes12 gateId = gk.createGate(_hashLeaf(member));
        assertFalse(gk.isAllowed(_randomAddress(), gateId, abi.encode(new bytes32[](0))));
    }

    function testSingleMemberGateWithInvalidProof() public {
        address member = _randomAddress();
        bytes12 gateId = gk.createGate(_hashLeaf(member));

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = _randomBytes32();
        bytes memory userData = abi.encode(proof);

        assertFalse(gk.isAllowed(member, gateId, userData));
    }

    function testMultiMemberGatePositive() public {
        address[4] memory members = _randomAllowList();
        bytes12 gateId = gk.createGate(_constructTree(members));

        address member = members[0];

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = _hashLeaf(members[1]);
        proof[1] = _hashNode(_hashLeaf(members[2]), _hashLeaf(members[3]));
        bytes memory userData = abi.encode(proof);

        assertTrue(gk.isAllowed(member, gateId, userData));
    }

    function testMultiMemberGateNegative() public {
        address[4] memory members = _randomAllowList();
        bytes12 gateId = gk.createGate(_constructTree(members));

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = _hashLeaf(members[1]);
        proof[1] = _hashNode(_hashLeaf(members[2]), _hashLeaf(members[3]));
        bytes memory userData = abi.encode(proof);

        assertFalse(gk.isAllowed(_randomAddress(), gateId, userData));
    }

    function testMultiMemberGateWithInvalidProof() public {
        address[4] memory members = _randomAllowList();
        bytes12 gateId = gk.createGate(_constructTree(members));

        address member = members[0];

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = _randomBytes32();
        proof[1] = _randomBytes32();
        bytes memory userData = abi.encode(proof);

        assertFalse(gk.isAllowed(member, gateId, userData));
    }

    function testSeparateGates() public {
        address[4] memory members1 = _randomAllowList();
        bytes12 gateId1 = gk.createGate(_constructTree(members1));

        address[4] memory members2 = _randomAllowList();
        bytes12 gateId2 = gk.createGate(_constructTree(members2));

        address member1 = members1[0];
        address member2 = members2[3];

        bytes32[] memory proof1 = new bytes32[](2);
        proof1[0] = _hashLeaf(members1[1]);
        proof1[1] = _hashNode(_hashLeaf(members1[2]), _hashLeaf(members1[3]));
        bytes memory userData1 = abi.encode(proof1);

        bytes32[] memory proof2 = new bytes32[](2);
        proof2[0] = _hashLeaf(members2[2]);
        proof2[1] = _hashNode(_hashLeaf(members2[0]), _hashLeaf(members2[1]));
        bytes memory userData2 = abi.encode(proof2);

        assertEq(gk.isAllowed(member1, gateId1, userData1), true);
        assertEq(gk.isAllowed(member2, gateId2, userData2), true);
        assertEq(gk.isAllowed(member2, gateId1, userData1), false);
        assertEq(gk.isAllowed(member1, gateId2, userData2), false);
    }
}
