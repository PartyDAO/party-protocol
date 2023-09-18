// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./IGateKeeper.sol";
import "openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { ContributionRouter } from "../crowdfund/ContributionRouter.sol";

/// @notice A gateKeeper that implements a simple allow list per gate.
contract AllowListGateKeeper is IGateKeeper {
    /// @notice The address of the canonical contribution router.
    address public immutable CONTRIBUTION_ROUTER;
    uint96 private _lastId;
    /// @notice Get the merkle root used by a gate identified by it's `id`.
    mapping(uint96 => bytes32) public merkleRoots;

    constructor(address contributionRouter) {
        CONTRIBUTION_ROUTER = contributionRouter;
    }

    /// @inheritdoc IGateKeeper
    function isAllowed(
        address participant,
        bytes12 id,
        bytes memory userData
    ) external view returns (bool) {
        if (participant == CONTRIBUTION_ROUTER) {
            participant = ContributionRouter(payable(CONTRIBUTION_ROUTER)).caller();
        }
        bytes32[] memory proof = abi.decode(userData, (bytes32[]));
        bytes32 leaf;
        assembly {
            mstore(0x00, participant)
            leaf := keccak256(0x0C, 20)
        }

        return MerkleProof.verify(proof, merkleRoots[uint96(id)], leaf);
    }

    /// @notice Create a new gate using `merkleRoot` to implement the allowlist.
    /// @param merkleRoot The merkle root to use for the allowlist.
    /// @return id The ID of the new gate.
    function createGate(bytes32 merkleRoot) external returns (bytes12 id) {
        uint96 id_ = ++_lastId;
        merkleRoots[id_] = merkleRoot;
        id = bytes12(id_);
    }
}
