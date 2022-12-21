// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./Party.sol";
import "./IPartyFactory.sol";
import "../utils/LibRawResult.sol";

contract PartyList {
    using LibRawResult for bytes;

    struct MintArgs {
        // The party from which the token is being minted
        Party party;
        // The address of the party member for whom the token is being minted
        address member;
        // The voting power of the token
        uint96 votingPower;
        // A number used to prevent double-minting
        uint256 nonce;
        // The address to delegate voting power to
        address delegate;
        // A set of data used to verify the validity of the minting
        bytes32[] proof;
    }

    event ListCreated(Party party, bytes32 merkleRoot);

    error ListAlreadyExistsError(Party party, bytes32 merkleRoot);
    error InvalidProofError(bytes32[] proof);
    error AlreadyMintedError(bytes32 leaf);
    error UnauthorizedError();

    /// @notice party address => merkle root
    mapping(Party => bytes32) public listMerkleRoots;
    /// @notice party address => leaf => minted
    mapping(Party => mapping(bytes32 => bool)) public minted;

    IGlobals private immutable _GLOBALS;

    // Set the `Globals` contract.
    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    modifier onlyPartyFactory() {
        if (msg.sender != _GLOBALS.getAddress(LibGlobals.GLOBAL_PARTY_FACTORY))
            revert UnauthorizedError();
        _;
    }

    /**
     * @notice Creates a new list for a party and mints the creator their card.
     * @dev Only the `PartyFactory` address is authorized to create lists.
     * @param party The party to create the list for.
     * @param merkleRoot The root of the Merkle tree for the list.
     * @param creator The address of the creator of the list.
     * @param creatorVotingPower The voting power of the creator.
     * @param creatorDelegate The address of the delegate of the creator.
     */
    function createList(
        Party party,
        bytes32 merkleRoot,
        address creator,
        uint96 creatorVotingPower,
        address creatorDelegate
    ) external onlyPartyFactory {
        bytes32 root = listMerkleRoots[party];
        if (root != bytes32(0)) revert ListAlreadyExistsError(party, root);

        listMerkleRoots[party] = merkleRoot;

        if (creator != address(0) && creatorVotingPower > 0) {
            party.mint(creator, creatorVotingPower, creatorDelegate);
        }

        emit ListCreated(party, merkleRoot);
    }

    /**
     * @notice Mints a party card for a member from the party's list.
     * @param args The arguments for minting a party card.
     * @return tokenId The ID of the newly minted party card.
     */
    function mint(MintArgs memory args) external returns (uint256 tokenId) {
        (bool allowed, bytes32 leaf) = _verify(
            args.party,
            args.member,
            args.votingPower,
            args.nonce,
            args.proof
        );

        if (!allowed) revert InvalidProofError(args.proof);
        if (minted[args.party][leaf]) revert AlreadyMintedError(leaf);

        minted[args.party][leaf] = true;

        return args.party.mint(args.member, args.votingPower, args.delegate);
    }

    /**
     * @notice Mints party cards for members from the party's list.
     * @param args The arguments for minting party cards.
     * @param revertOnFailure A boolean indicating if the function should revert if a mint fails.
     */
    function batchMint(MintArgs[] memory args, bool revertOnFailure) external {
        for (uint256 i; i < args.length; ++i) {
            (bool s, bytes memory r) = address(this).delegatecall(
                abi.encodeCall(this.mint, (args[i]))
            );
            if (revertOnFailure && !s) {
                r.rawRevert();
            }
        }
    }

    /**
     * @notice Checks if a given member is allowed to mint from a party's list.
     * @param party The party for which the `member` is being checked.
     * @param member The address of the member to check.
     * @param votingPower The voting power of the `member` in the `party`.
     * @param nonce A nonce associated with the mint used to prevent double-minting.
     * @param proof A set of data used to verify the validity of the minting.
     * @return allowed A boolean indicating if the `member` is allowed to mint.
     */
    function isAllowed(
        Party party,
        address member,
        uint96 votingPower,
        uint256 nonce,
        bytes32[] memory proof
    ) public view returns (bool) {
        (bool allowed, bytes32 leaf) = _verify(party, member, votingPower, nonce, proof);
        return allowed && !minted[party][leaf];
    }

    function _verify(
        Party party,
        address member,
        uint96 votingPower,
        uint256 nonce,
        bytes32[] memory proof
    ) private view returns (bool allowed, bytes32 leaf) {
        assembly {
            // leaf = keccak256(abi.encodePacked(member, votingPower, nonce))
            mstore(0, shl(96, member))
            mstore(20, shl(160, votingPower))
            mstore(32, nonce)
            leaf := keccak256(0, 64)
        }

        allowed = MerkleProof.verify(proof, listMerkleRoots[party], leaf);
    }
}
