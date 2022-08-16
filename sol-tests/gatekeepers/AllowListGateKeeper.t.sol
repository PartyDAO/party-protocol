// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/gatekeepers/AllowListGateKeeper.sol";
import "../TestUtils.sol";

contract AllowListGateKeeperTest is Test, TestUtils {
    AllowListGateKeeper gk;

    // Merkle roots and proofs for test cases were generated off-chain using merkletreejs

    address[] group1;
    bytes32 merkleRoot1;

    address[] group2;
    bytes32 merkleRoot2;

    constructor() {
        gk = new AllowListGateKeeper();

        group1.push(0x2f45fd5988e20Fc7B63a54e8B45789261558CA0f);
        group1.push(0xfC9d809c16375C080598f152dc2DAe4B09FA1a86);
        group1.push(0xE0CD8cf8Ce58973352206f0402275C197800E953);
        group1.push(0x2657d94b2559cFAe3bB28de86A3131780b1774b5);
        group1.push(0x94d1272908fF6505A14C39A52B0689D59F2a2Bb6);
        group1.push(0xF01517a133Fd749ebC661a08f66EFe6B83F1bC8E);
        group1.push(0x0f06cff1C456Bcd8D7b8391fd298120bef3A9c9D);

        merkleRoot1 = 0x7c359e2d8d5cadd300f4c406ac1cd47ab12d4669cc595f1d5fe62bf747e51b20;

        group2.push(0xd9A284367b6D3e25A91c91b5A430AF2593886EB9);
        group2.push(0xE6b3367318C5e11a6eED3Cd0D850eC06A02E9b90);
        group2.push(0x88C0e901bd1fd1a77BdA342f0d2210fDC71Cef6B);
        group2.push(0x7231C364597f3BfDB72Cf52b197cc59111e71794);
        group2.push(0x043aEd06383F290Ee28FA02794Ec7215CA099683);
        group2.push(0x0c95931d95694B3ef74071241827C09f25d40620);
        group2.push(0x417f3b59eF57C641283C2300fae0f27fe98D518C);

        merkleRoot2 = 0x1f069a91c8331f3dc597b97f3e191f65141273921eb9b2dc1d036bcbbd43baf2;
    }

    function testUniqueGateIds() public {
        bytes12 gateId1 = gk.createGate(merkleRoot1);
        bytes12 gateId2 = gk.createGate(merkleRoot2);
        assertTrue(gateId1 != gateId2);
    }

    function testSingleMemberGatePositive() public {
        address[] memory group = new address[](1);
        group[0] = _randomAddress();
        bytes12 gateId = gk.createGate(keccak256(abi.encodePacked(group[0])));
        assertTrue(gk.isAllowed(group[0], gateId, abi.encode(new bytes32[](0))));
    }

    function testSingleMemberGateNegative() public {
        address[] memory group = new address[](1);
        group[0] = _randomAddress();
        bytes12 gateId = gk.createGate(keccak256(abi.encodePacked(group[0])));
        assertFalse(gk.isAllowed(_randomAddress(), gateId, abi.encode(new bytes32[](0))));
    }

    function testMultiMemberGatePositive() public {
        bytes12 gateId = gk.createGate(merkleRoot1);

        address participant = group1[0];

        bytes32[] memory proof = new bytes32[](3);
        proof[0] = 0xaf69b891d2f70be157fb251366c9da444977b60ba55a8b1d48af520d94803eef;
        proof[1] = 0xbda2fb5ee52ef5806c18fa06f9413a96753625b03ad8cb12b927b8376efcdea8;
        proof[2] = 0x5daae69c2378cfb2febedec2061fb3e52d9e7ef216921111853f911de58f2409;

        bytes memory userData = abi.encode(proof);

        assertTrue(gk.isAllowed(participant, gateId, userData));
    }

    function testMultiMemberGateNegative() public {
        bytes12 gateId = gk.createGate(merkleRoot1);

        address participant = _randomAddress();

        bytes32[] memory proof = new bytes32[](3);
        proof[0] = 0xaf69b891d2f70be157fb251366c9da444977b60ba55a8b1d48af520d94803eef;
        proof[1] = 0xbda2fb5ee52ef5806c18fa06f9413a96753625b03ad8cb12b927b8376efcdea8;
        proof[2] = 0x5daae69c2378cfb2febedec2061fb3e52d9e7ef216921111853f911de58f2409;

        bytes memory userData = abi.encode(proof);

        assertFalse(gk.isAllowed(participant, gateId, userData));
    }

    function testSeparateGates() public {
        bytes12 gateId1 = gk.createGate(merkleRoot1);
        bytes12 gateId2 = gk.createGate(merkleRoot2);

        address participant1 = group1[0];
        address participant2 = group2[0];

        bytes32[] memory proof1 = new bytes32[](3);
        proof1[0] = 0xaf69b891d2f70be157fb251366c9da444977b60ba55a8b1d48af520d94803eef;
        proof1[1] = 0xbda2fb5ee52ef5806c18fa06f9413a96753625b03ad8cb12b927b8376efcdea8;
        proof1[2] = 0x5daae69c2378cfb2febedec2061fb3e52d9e7ef216921111853f911de58f2409;
        bytes memory userData1 = abi.encode(proof1);

        bytes32[] memory proof2 = new bytes32[](3);
        proof2[0] = 0xb43744a84c18034912f037d5a3faf0168c12341c74dc9c271086d17125b17151;
        proof2[1] = 0x989e2542c6298b58e12d9a297461ad905f73310c07b447e02875934447ce3355;
        proof2[2] = 0x71c580d5a40008e51cb954a17fb79e78396b71ce69898f04de4d4971bb465b80;
        bytes memory userData2 = abi.encode(proof2);


        assertEq(gk.isAllowed(participant1, gateId1, userData1), true);
        assertEq(gk.isAllowed(participant2, gateId2, userData2), true);
        assertEq(gk.isAllowed(participant2, gateId1, userData1), false);
        assertEq(gk.isAllowed(participant1, gateId2, userData2), false);
    }
}
