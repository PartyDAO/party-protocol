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
        bytes32 merkleRoot = keccak256(abi.encodePacked(_randomUint256()));
        partyList.createList(party, merkleRoot);
        assertEq(partyList.listMerkleRoots(party), merkleRoot);
    }

    function test_createList_onlyPartyFactory() public {
        bytes32 merkleRoot = keccak256(abi.encodePacked(_randomUint256()));
        vm.prank(_randomAddress());
        vm.expectRevert(PartyList.UnauthorizedError.selector);
        partyList.createList(party, merkleRoot);
    }

    function test_createList_onlyOncePerParty() public {
        bytes32 merkleRoot = keccak256(abi.encodePacked(_randomUint256()));
        partyList.createList(party, merkleRoot);
        vm.expectRevert(
            abi.encodeWithSelector(PartyList.ListAlreadyExistsError.selector, party, merkleRoot)
        );
        partyList.createList(party, merkleRoot);
    }

    function test_mint_works() public {
        address member = _randomAddress();
        uint96 votingPower = 0.1e18;
        address delegate = _randomAddress();
        bytes32 merkleRoot = keccak256(abi.encodePacked(member, votingPower));
        partyList.createList(party, merkleRoot);
        uint256 tokenId = partyList.mint(party, member, votingPower, delegate, new bytes32[](0));
        assertEq(party.ownerOf(tokenId), member);
    }

    function test_mint_invalidProof() public {
        address member = _randomAddress();
        uint96 votingPower = 0.1e18;
        address delegate = _randomAddress();
        bytes32 merkleRoot = keccak256(abi.encodePacked(member, votingPower));
        partyList.createList(party, merkleRoot);
        vm.expectRevert(abi.encodeWithSelector(PartyList.InvalidProofError.selector));
        partyList.mint(party, member, votingPower, delegate, new bytes32[](1));
    }
}
