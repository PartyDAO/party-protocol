// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "solmate/utils/MerkleProofLib.sol";

import "./Party.sol";
import "./IPartyFactory.sol";

contract PartyList {
    error ListAlreadyExistsError(Party party, bytes32 merkleRoot);
    error UnauthorizedError();
    error InvalidProofError();

    mapping(Party => bytes32) public listMerkleRoots;

    IGlobals private immutable _GLOBALS;

    // Set the `Globals` contract.
    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    function createList(Party party, bytes32 merkleRoot) external {
        if (msg.sender != _GLOBALS.getAddress(LibGlobals.GLOBAL_PARTY_FACTORY))
            revert UnauthorizedError();

        bytes32 root = listMerkleRoots[party];
        if (root != bytes32(0)) revert ListAlreadyExistsError(party, root);

        listMerkleRoots[party] = merkleRoot;
    }

    function mint(
        Party party,
        address member,
        uint96 votingPower,
        address delegate,
        bytes32[] calldata proof
    ) public returns (uint256 tokenId) {
        if (!isAllowed(party, member, votingPower, proof)) revert InvalidProofError();
        return party.mint(member, votingPower, delegate);
    }

    function batchMint(
        Party party,
        address[] calldata members,
        uint96[] calldata votingPowers,
        address[] calldata delegates,
        bytes32[][] calldata proofs
    ) external returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](members.length);
        for (uint256 i; i < members.length; ++i) {
            tokenIds[0] = mint(party, members[i], votingPowers[i], delegates[i], proofs[i]);
        }
    }

    function isAllowed(
        Party party,
        address member,
        uint96 votingPower,
        bytes32[] calldata proof
    ) public view returns (bool) {
        bytes32 leaf;
        assembly {
            // leaf = keccak256(abi.encodePacked(member, votingPower))
            mstore(0, shl(96, member))
            mstore(20, shl(160, votingPower))
            leaf := keccak256(0, 32)
        }

        return MerkleProofLib.verify(proof, listMerkleRoots[party], leaf);
    }
}
