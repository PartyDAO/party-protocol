// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { Party, PartyGovernanceNFT } from "../../contracts/party/Party.sol";
import { AddPartyCardsAuthority } from "../../contracts/authorities/AddPartyCardsAuthority.sol";

contract AddPartyCardsAuthorityTest is SetupPartyHelper {
    AddPartyCardsAuthority authority;

    constructor() SetupPartyHelper(false) {}

    function setUp() public override {
        super.setUp();

        authority = new AddPartyCardsAuthority();

        // Add as authority to the Party to be able to mint cards
        vm.prank(address(party));
        party.addAuthority(address(authority));
    }

    function test_addPartyCards_single() public {
        address[] memory newPartyMembers = new address[](1);
        newPartyMembers[0] = _randomAddress();
        uint96[] memory newPartyMemberVotingPowers = new uint96[](1);
        newPartyMemberVotingPowers[0] = 100;
        address[] memory initialDelegates = new address[](1);
        initialDelegates[0] = _randomAddress();

        uint96 totalVotingPowerBefore = party.getGovernanceValues().totalVotingPower;

        vm.prank(address(party));
        authority.addPartyCards(newPartyMembers, newPartyMemberVotingPowers, initialDelegates);

        assertEq(
            party.getGovernanceValues().totalVotingPower - totalVotingPowerBefore,
            newPartyMemberVotingPowers[0]
        );
        assertEq(party.votingPowerByTokenId(party.tokenCount()), newPartyMemberVotingPowers[0]);
        assertEq(
            party.getVotingPowerAt(initialDelegates[0], uint40(block.timestamp)),
            newPartyMemberVotingPowers[0]
        );
        assertEq(party.delegationsByVoter(newPartyMembers[0]), initialDelegates[0]);
    }

    function test_addPartyCards_multiple() public {
        address[] memory newPartyMembers = new address[](3);
        newPartyMembers[0] = _randomAddress();
        newPartyMembers[1] = _randomAddress();
        newPartyMembers[2] = _randomAddress();
        uint96[] memory newPartyMemberVotingPowers = new uint96[](3);
        newPartyMemberVotingPowers[0] = 100;
        newPartyMemberVotingPowers[1] = 200;
        newPartyMemberVotingPowers[2] = 300;
        address[] memory initialDelegates = new address[](3);
        initialDelegates[0] = _randomAddress();
        initialDelegates[1] = _randomAddress();
        initialDelegates[2] = _randomAddress();

        uint96 totalVotingPowerBefore = party.getGovernanceValues().totalVotingPower;
        uint96 tokenCount = party.tokenCount();

        vm.prank(address(party));
        authority.addPartyCards(newPartyMembers, newPartyMemberVotingPowers, initialDelegates);

        uint96 totalVotingPowerAdded;
        for (uint256 i; i < newPartyMembers.length; i++) {
            uint256 tokenId = tokenCount + i + 1;

            totalVotingPowerAdded += newPartyMemberVotingPowers[i];

            assertEq(party.votingPowerByTokenId(tokenId), newPartyMemberVotingPowers[i]);
            assertEq(
                party.getVotingPowerAt(initialDelegates[i], uint40(block.timestamp)),
                newPartyMemberVotingPowers[i]
            );
            assertEq(party.delegationsByVoter(newPartyMembers[i]), initialDelegates[i]);
        }
        assertEq(
            party.getGovernanceValues().totalVotingPower - totalVotingPowerBefore,
            totalVotingPowerAdded
        );
    }

    function test_addPartyCards_multipleWithSameAddress() public {
        address[] memory newPartyMembers = new address[](3);
        newPartyMembers[0] = newPartyMembers[1] = newPartyMembers[2] = _randomAddress();
        uint96[] memory newPartyMemberVotingPowers = new uint96[](3);
        newPartyMemberVotingPowers[0] = 100;
        newPartyMemberVotingPowers[1] = 200;
        newPartyMemberVotingPowers[2] = 300;
        address[] memory initialDelegates = new address[](3);
        initialDelegates[0] = _randomAddress();
        initialDelegates[1] = _randomAddress();
        initialDelegates[2] = _randomAddress();

        uint96 totalVotingPowerBefore = party.getGovernanceValues().totalVotingPower;
        uint96 tokenCount = party.tokenCount();

        vm.prank(address(party));
        authority.addPartyCards(newPartyMembers, newPartyMemberVotingPowers, initialDelegates);

        uint96 totalVotingPowerAdded;
        for (uint256 i; i < newPartyMembers.length; i++) {
            uint256 tokenId = tokenCount + i + 1;

            totalVotingPowerAdded += newPartyMemberVotingPowers[i];

            assertEq(party.votingPowerByTokenId(tokenId), newPartyMemberVotingPowers[i]);
            // Should only allow setting the initial delegate, not changing it
            assertEq(party.delegationsByVoter(newPartyMembers[i]), initialDelegates[0]);
        }
        assertEq(
            party.getVotingPowerAt(initialDelegates[0], uint40(block.timestamp)),
            totalVotingPowerAdded
        );
        assertEq(
            party.getGovernanceValues().totalVotingPower - totalVotingPowerBefore,
            totalVotingPowerAdded
        );
    }

    function test_addPartyCards_onlyAuthority() public {
        address[] memory newPartyMembers = new address[](1);
        newPartyMembers[0] = _randomAddress();
        uint96[] memory newPartyMemberVotingPowers = new uint96[](1);
        newPartyMemberVotingPowers[0] = 100;
        address[] memory initialDelegates = new address[](1);
        initialDelegates[0] = address(0);

        AddPartyCardsAuthority notAuthority = new AddPartyCardsAuthority();
        vm.expectRevert(PartyGovernanceNFT.OnlyAuthorityError.selector);
        vm.prank(address(party));
        notAuthority.addPartyCards(newPartyMembers, newPartyMemberVotingPowers, initialDelegates);
    }

    function test_addPartyCard_cannotAddNoPartyCards() public {
        address[] memory newPartyMembers;
        uint96[] memory newPartyMemberVotingPowers;
        address[] memory initialDelegates;

        vm.expectRevert(AddPartyCardsAuthority.NoPartyMembers.selector);
        authority.addPartyCards(newPartyMembers, newPartyMemberVotingPowers, initialDelegates);
    }

    function test_addPartyCard_cannotAddZeroVotingPower() public {
        address[] memory newPartyMembers = new address[](1);
        newPartyMembers[0] = _randomAddress();
        uint96[] memory newPartyMemberVotingPowers = new uint96[](1);
        newPartyMemberVotingPowers[0] = 0;
        address[] memory initialDelegates = new address[](1);
        initialDelegates[0] = _randomAddress();

        vm.expectRevert(AddPartyCardsAuthority.InvalidPartyMemberVotingPower.selector);
        authority.addPartyCards(newPartyMembers, newPartyMemberVotingPowers, initialDelegates);
    }
}
