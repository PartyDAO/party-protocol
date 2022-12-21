// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/party/PartyList.sol";
import "../../contracts/globals/Globals.sol";
import "../crowdfund/MockParty.sol";
import "../TestUtils.sol";

contract PartyListTest is Test, TestUtils {
    Globals globals = new Globals(address(this));
    PartyList partyList = new PartyList(globals);
    Party party = Party(payable(address(new MockParty())));

    constructor() {
        // Set party factory to this address so that we have authority to create list
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(this));
    }

    function test_createList_works() public {
        address creator = _randomAddress();
        uint96 creatorVotingPower = 0.3e18;
        address creatorDelegate = _randomAddress();
        bytes32 merkleRoot = keccak256(abi.encodePacked(_randomUint256()));
        partyList.createList(party, merkleRoot, creator, creatorVotingPower, creatorDelegate);
        assertEq(partyList.listMerkleRoots(party), merkleRoot);
    }

    function test_createList_onlyPartyFactory() public {
        address creator = _randomAddress();
        uint96 creatorVotingPower = 0.3e18;
        address creatorDelegate = _randomAddress();
        bytes32 merkleRoot = keccak256(abi.encodePacked(_randomUint256()));
        vm.prank(_randomAddress());
        vm.expectRevert(PartyList.UnauthorizedError.selector);
        partyList.createList(party, merkleRoot, creator, creatorVotingPower, creatorDelegate);
    }

    function test_createList_onlyOncePerParty() public {
        address creator = _randomAddress();
        uint96 creatorVotingPower = 0.3e18;
        address creatorDelegate = _randomAddress();
        bytes32 merkleRoot = keccak256(abi.encodePacked(_randomUint256()));
        partyList.createList(party, merkleRoot, creator, creatorVotingPower, creatorDelegate);
        vm.expectRevert(
            abi.encodeWithSelector(PartyList.ListAlreadyExistsError.selector, party, merkleRoot)
        );
        partyList.createList(party, merkleRoot, creator, creatorVotingPower, creatorDelegate);
    }

    function test_mint_works() public {
        address member = _randomAddress();
        uint96 votingPower = 0.1e18;
        uint256 nonce = _randomUint256();
        address delegate = _randomAddress();
        bytes32 merkleRoot = keccak256(abi.encodePacked(member, votingPower, nonce));
        partyList.createList(party, merkleRoot, address(0), 0, address(0));
        uint256 tokenId = partyList.mint(
            PartyList.MintArgs({
                party: party,
                member: member,
                votingPower: votingPower,
                nonce: nonce,
                delegate: delegate,
                proof: new bytes32[](0)
            })
        );
        assertEq(party.ownerOf(tokenId), member);
    }

    function test_mint_cannotMintTwice() public {
        address member = _randomAddress();
        uint96 votingPower = 0.1e18;
        uint256 nonce = _randomUint256();
        address delegate = _randomAddress();
        bytes32 merkleRoot = keccak256(abi.encodePacked(member, votingPower, nonce));
        partyList.createList(party, merkleRoot, address(0), 0, address(0));
        partyList.mint(
            PartyList.MintArgs({
                party: party,
                member: member,
                votingPower: votingPower,
                nonce: nonce,
                delegate: delegate,
                proof: new bytes32[](0)
            })
        );
        vm.expectRevert(abi.encodeWithSelector(PartyList.AlreadyMintedError.selector, merkleRoot));
        partyList.mint(
            PartyList.MintArgs({
                party: party,
                member: member,
                votingPower: votingPower,
                nonce: nonce,
                delegate: delegate,
                proof: new bytes32[](0)
            })
        );
    }

    function test_mint_invalidProof() public {
        address member = _randomAddress();
        uint96 votingPower = 0.1e18;
        uint256 nonce = _randomUint256();
        address delegate = _randomAddress();
        bytes32 merkleRoot = keccak256(abi.encodePacked(member, votingPower, nonce));
        bytes32[] memory proof = new bytes32[](1);
        partyList.createList(party, merkleRoot, address(0), 0, address(0));
        vm.expectRevert(abi.encodeWithSelector(PartyList.InvalidProofError.selector, proof));
        partyList.mint(
            PartyList.MintArgs({
                party: party,
                member: member,
                votingPower: votingPower,
                nonce: nonce,
                delegate: delegate,
                proof: proof
            })
        );
    }
}
