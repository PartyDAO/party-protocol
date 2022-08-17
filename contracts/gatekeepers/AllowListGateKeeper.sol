// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./IGateKeeper.sol";
import "openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// A GateKeeper that implements a simple allow list (really a mapping) per gate.
contract AllowListGateKeeper is IGateKeeper {
    uint96 private _lastId;
    // gate ID -> merkle root
    mapping(uint96 => bytes32) public merkleRoots;

    function isAllowed(
        address participant,
        bytes12 id,
        bytes memory userData
    ) external view returns (bool) {
        bytes32[] memory proof = abi.decode(userData, (bytes32[]));
        bytes32 leaf;
        assembly {
            mstore(0x00, participant)
            leaf := keccak256(0x0C, 20)
        }

        return MerkleProof.verify(proof, merkleRoots[uint96(id)], leaf);
    }

    function createGate(bytes32 merkleRoot) external returns (bytes12 id) {
        uint96 id_ = ++_lastId;
        merkleRoots[id_] = merkleRoot;
        id = bytes12(id_);
    }
}
