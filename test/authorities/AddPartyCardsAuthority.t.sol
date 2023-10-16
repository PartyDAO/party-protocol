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

        uint96 votingPowerBefore = party.getVotingPowerAt(
            newPartyMembers[0],
            uint40(block.timestamp)
        );
        uint96 totalVotingPowerBefore = party.getGovernanceValues().totalVotingPower;

        vm.prank(address(party));
        authority.addPartyCards(newPartyMembers, newPartyMemberVotingPowers);

        assertEq(
            party.getGovernanceValues().totalVotingPower - totalVotingPowerBefore,
            newPartyMemberVotingPowers[0]
        );
        assertEq(
            party.getVotingPowerAt(newPartyMembers[0], uint40(block.timestamp)) - votingPowerBefore,
            newPartyMemberVotingPowers[0]
        );
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

        uint96 votingPowerBefore = party.getVotingPowerAt(
            newPartyMembers[0],
            uint40(block.timestamp)
        );
        uint96 totalVotingPowerBefore = party.getGovernanceValues().totalVotingPower;

        vm.prank(address(party));
        authority.addPartyCards(newPartyMembers, newPartyMemberVotingPowers);

        uint96 totalVotingPowerAdded;
        for (uint256 i; i < newPartyMembers.length; i++) {
            totalVotingPowerAdded += newPartyMemberVotingPowers[i];

            assertEq(
                party.getVotingPowerAt(newPartyMembers[i], uint40(block.timestamp)) -
                    votingPowerBefore,
                newPartyMemberVotingPowers[i]
            );
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

        uint96 votingPowerBefore = party.getVotingPowerAt(
            newPartyMembers[0],
            uint40(block.timestamp)
        );
        uint96 totalVotingPowerBefore = party.getGovernanceValues().totalVotingPower;

        vm.prank(address(party));
        authority.addPartyCards(newPartyMembers, newPartyMemberVotingPowers);

        uint96 totalVotingPowerAdded;
        for (uint256 i; i < newPartyMembers.length; i++) {
            totalVotingPowerAdded += newPartyMemberVotingPowers[i];

            assertEq(
                party.getVotingPowerAt(newPartyMembers[i], uint40(block.timestamp)) -
                    votingPowerBefore,
                newPartyMemberVotingPowers[i]
            );
        }
        assertEq(
            party.getGovernanceValues().totalVotingPower - totalVotingPowerBefore,
            totalVotingPowerAdded
        );
    }

    function test_addPartyCards_onlyParty() public {
        address[] memory newPartyMembers = new address[](1);
        newPartyMembers[0] = _randomAddress();
        uint96[] memory newPartyMemberVotingPowers = new uint96[](1);
        newPartyMemberVotingPowers[0] = 100;

        vm.expectRevert(PartyGovernanceNFT.OnlyAuthorityError.selector);
        authority.addPartyCards(newPartyMembers, newPartyMemberVotingPowers);
    }

    function test_addPartyCard_cannotAddNoPartyCards() public {
        address[] memory newPartyMembers = new address[](0);
        uint96[] memory newPartyMemberVotingPowers;

        // TODO: Specify expected error
        vm.expectRevert();
        authority.addPartyCards(newPartyMembers, newPartyMemberVotingPowers);
    }

    function test_addPartyCard_cannotAddZeroVotingPower() public {
        address[] memory newPartyMembers = new address[](1);
        newPartyMembers[0] = _randomAddress();
        uint96[] memory newPartyMemberVotingPowers = new uint96[](1);
        newPartyMemberVotingPowers[0] = 0;

        // TODO: Specify expected error
        vm.expectRevert();
        authority.addPartyCards(newPartyMembers, newPartyMemberVotingPowers);
    }
}
