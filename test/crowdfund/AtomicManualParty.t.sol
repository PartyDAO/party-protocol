// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { AtomicManualParty } from "../../contracts/crowdfund/AtomicManualParty.sol";
import { Party } from "../../contracts/party/Party.sol";
import { IERC721 } from "../../contracts/tokens/IERC721.sol";
import { MetadataProvider } from "../../contracts/renderers/MetadataProvider.sol";
import { IMetadataProvider } from "../../contracts/renderers/IMetadataProvider.sol";

contract AtomicManualPartyTest is SetupPartyHelper {
    event PartyCreated(
        Party indexed party,
        Party.PartyOptions opts,
        IERC721[] preciousTokens,
        uint256[] preciousTokenIds,
        address creator
    );
    event AtomicManualPartyCreated(
        Party indexed party,
        address[] partyMembers,
        uint96[] partyMemberVotingPowers,
        Party.PartyOptions opts,
        IERC721[] preciousTokens,
        uint256[] preciousTokenIds,
        uint40 rageQuitTimestamp,
        address creator
    );
    event ProviderSet(address indexed instance, IMetadataProvider indexed provider);

    AtomicManualParty private atomicManualParty;

    constructor() SetupPartyHelper(false) {}

    function setUp() public override {
        super.setUp();
        atomicManualParty = new AtomicManualParty(partyFactory);
    }

    function test_createAtomicManualParty() public {
        Party.PartyOptions memory opts;
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.voteDuration = 1 hours;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 180;

        address[] memory partyMembers = new address[](2);
        uint96[] memory partyMemberVotingPower = new uint96[](2);

        partyMembers[0] = john;
        partyMembers[1] = danny;

        partyMemberVotingPower[0] = 100;
        partyMemberVotingPower[1] = 80;

        // Not checking address of the party
        vm.expectEmit(false, true, true, true);
        emit PartyCreated(
            Party(payable(0)),
            opts,
            preciousTokens,
            preciousTokenIds,
            address(atomicManualParty)
        );
        vm.expectEmit(false, true, true, true);
        emit AtomicManualPartyCreated(
            Party(payable(0)),
            partyMembers,
            partyMemberVotingPower,
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            address(this)
        );
        // total voting power ignored
        opts.governance.totalVotingPower = 100;
        Party atomicParty = atomicManualParty.createParty(
            Party(payable(address(party.implementation()))),
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            partyMembers,
            partyMemberVotingPower,
            new address[](0)
        );

        // Ensure `atomicManualParty` is not an authority after creation
        assertFalse(atomicParty.isAuthority(address(atomicManualParty)));
        assertEq(atomicParty.getGovernanceValues().totalVotingPower, 180);

        // Ensure holders match input
        assertEq(atomicParty.getVotingPowerAt(john, uint40(block.timestamp), 0), 100);
        assertEq(atomicParty.getVotingPowerAt(danny, uint40(block.timestamp), 0), 80);
    }

    function test_createAtomicManualPartyWithMetadata() public {
        Party.PartyOptions memory opts;
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.voteDuration = 1 hours;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 180;

        address[] memory partyMembers = new address[](2);
        uint96[] memory partyMemberVotingPower = new uint96[](2);

        partyMembers[0] = john;
        partyMembers[1] = danny;

        partyMemberVotingPower[0] = 100;
        partyMemberVotingPower[1] = 80;

        // Not checking address of the party
        vm.expectEmit(false, true, true, true);
        emit PartyCreated(
            Party(payable(0)),
            opts,
            preciousTokens,
            preciousTokenIds,
            address(atomicManualParty)
        );
        vm.expectEmit(false, true, true, true);
        emit ProviderSet(address(0), IMetadataProvider(address(0)));
        Party atomicParty = atomicManualParty.createPartyWithMetadata(
            Party(payable(address(party.implementation()))),
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            MetadataProvider(address(0)),
            "",
            partyMembers,
            partyMemberVotingPower,
            new address[](0)
        );

        // Ensure `atomicManualParty` is not an authority after creation
        assertFalse(party.isAuthority(address(atomicManualParty)));

        // Ensure holders match input
        assertEq(atomicParty.getVotingPowerAt(john, uint40(block.timestamp), 0), 100);
        assertEq(atomicParty.getVotingPowerAt(danny, uint40(block.timestamp), 0), 80);
    }

    function test_createAtomicManualPartyArityMismatch() public {
        Party.PartyOptions memory opts;
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.voteDuration = 1 hours;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 180;

        address[] memory partyMembers = new address[](3);
        uint96[] memory partyMemberVotingPower = new uint96[](2);

        partyMembers[0] = john;
        partyMembers[1] = danny;
        partyMembers[2] = steve;

        partyMemberVotingPower[0] = 100;
        partyMemberVotingPower[1] = 80;

        Party partyImpl = Party(payable(address(party.implementation())));
        vm.expectRevert(AtomicManualParty.PartyMembersArityMismatch.selector);
        atomicManualParty.createParty(
            partyImpl,
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            partyMembers,
            partyMemberVotingPower,
            new address[](0)
        );
    }

    function test_createAtomicManualParty_noMembers() public {
        Party.PartyOptions memory opts;
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.voteDuration = 1 hours;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 180;

        address[] memory partyMembers = new address[](0);
        uint96[] memory partyMemberVotingPower = new uint96[](0);

        Party partyImpl = Party(payable(address(party.implementation())));
        vm.expectRevert(AtomicManualParty.NoPartyMembers.selector);
        atomicManualParty.createParty(
            partyImpl,
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            partyMembers,
            partyMemberVotingPower,
            new address[](0)
        );
    }

    function test_createAtomicManualParty_multipleCardsToSameAddress() public {
        Party.PartyOptions memory opts;
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.voteDuration = 1 hours;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 260;

        address[] memory partyMembers = new address[](3);
        uint96[] memory partyMemberVotingPower = new uint96[](3);

        partyMembers[0] = john;
        partyMembers[1] = danny;
        partyMembers[2] = john;

        partyMemberVotingPower[0] = 100;
        partyMemberVotingPower[1] = 80;
        partyMemberVotingPower[2] = 80;

        // Not checking address of the party
        vm.expectEmit(false, true, true, true);
        emit PartyCreated(
            Party(payable(0)),
            opts,
            preciousTokens,
            preciousTokenIds,
            address(atomicManualParty)
        );
        Party atomicParty = atomicManualParty.createParty(
            Party(payable(address(party.implementation()))),
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            partyMembers,
            partyMemberVotingPower,
            new address[](0)
        );

        // Ensure `atomicManualParty` is not an authority after creation
        assertFalse(atomicParty.isAuthority(address(atomicManualParty)));
        assertEq(atomicParty.getGovernanceValues().totalVotingPower, 260);
        assertEq(atomicParty.ownerOf(1), john);
        assertEq(atomicParty.ownerOf(2), danny);
        assertEq(atomicParty.ownerOf(3), john);

        // Ensure holders match input
        assertEq(atomicParty.getVotingPowerAt(john, uint40(block.timestamp), 0), 180);
        assertEq(atomicParty.getVotingPowerAt(danny, uint40(block.timestamp), 0), 80);
    }

    function test_atomicManualParty_invalidPartyMember() public {
        Party.PartyOptions memory opts;
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.voteDuration = 1 hours;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 180;

        address[] memory partyMembers = new address[](2);
        uint96[] memory partyMemberVotingPower = new uint96[](2);

        partyMembers[0] = john;
        partyMembers[1] = address(0);

        partyMemberVotingPower[0] = 100;
        partyMemberVotingPower[1] = 80;

        Party partyImpl = Party(payable(address(party.implementation())));

        vm.expectRevert(AtomicManualParty.InvalidPartyMember.selector);
        atomicManualParty.createParty(
            partyImpl,
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            partyMembers,
            partyMemberVotingPower,
            new address[](0)
        );
    }

    function test_atomicManualParty_invalidPartyMemberVotingPower() public {
        Party.PartyOptions memory opts;
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.voteDuration = 1 hours;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 180;

        address[] memory partyMembers = new address[](2);
        uint96[] memory partyMemberVotingPower = new uint96[](2);

        partyMembers[0] = john;
        partyMembers[1] = danny;

        partyMemberVotingPower[0] = 100;
        partyMemberVotingPower[1] = 0;

        Party partyImpl = Party(payable(address(party.implementation())));

        vm.expectRevert(AtomicManualParty.InvalidPartyMemberVotingPower.selector);
        atomicManualParty.createParty(
            partyImpl,
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            partyMembers,
            partyMemberVotingPower,
            new address[](0)
        );
    }

    function test_atomicManualParty_additionalAuthorities() public {
        Party.PartyOptions memory opts;
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.voteDuration = 2 hours;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 180;

        address[] memory partyMembers = new address[](2);
        uint96[] memory partyMemberVotingPower = new uint96[](2);

        partyMembers[0] = john;
        partyMembers[1] = danny;

        partyMemberVotingPower[0] = 100;
        partyMemberVotingPower[1] = 80;

        // Not checking address of the party
        vm.expectEmit(false, true, true, true);
        emit PartyCreated(
            Party(payable(0)),
            opts,
            preciousTokens,
            preciousTokenIds,
            address(atomicManualParty)
        );
        vm.expectEmit(false, true, true, true);
        emit AtomicManualPartyCreated(
            Party(payable(0)),
            partyMembers,
            partyMemberVotingPower,
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            address(this)
        );

        address[] memory authorities = new address[](2);
        authorities[0] = _randomAddress();
        authorities[1] = _randomAddress();

        // total voting power ignored
        opts.governance.totalVotingPower = 100;
        Party atomicParty = atomicManualParty.createParty(
            partyImpl,
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            partyMembers,
            partyMemberVotingPower,
            authorities
        );

        // Ensure `atomicManualParty` is not an authority after creation
        // Ensure `atomicManualParty` is not an authority after creation
        assertFalse(atomicParty.isAuthority(address(atomicManualParty)));
        // Ensure authorities passed are authorities
        assertTrue(atomicParty.isAuthority(authorities[0]));
        assertTrue(atomicParty.isAuthority(authorities[1]));

        assertEq(atomicParty.getGovernanceValues().totalVotingPower, 180);

        // Ensure holders match input
        assertEq(atomicParty.getVotingPowerAt(john, uint40(block.timestamp), 0), 100);
        assertEq(atomicParty.getVotingPowerAt(danny, uint40(block.timestamp), 0), 80);
    }

    function test_createAtomicManualPartyWithMetadata_additionalAuthorities() public {
        Party.PartyOptions memory opts;
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.voteDuration = 1 hours;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 180;

        address[] memory partyMembers = new address[](2);
        uint96[] memory partyMemberVotingPower = new uint96[](2);

        partyMembers[0] = john;
        partyMembers[1] = danny;

        partyMemberVotingPower[0] = 100;
        partyMemberVotingPower[1] = 80;

        address[] memory authorities = new address[](2);
        authorities[0] = _randomAddress();
        authorities[1] = _randomAddress();

        // Not checking address of the party
        vm.expectEmit(false, true, true, true);
        emit PartyCreated(
            Party(payable(0)),
            opts,
            preciousTokens,
            preciousTokenIds,
            address(atomicManualParty)
        );
        vm.expectEmit(false, true, true, true);
        emit ProviderSet(address(0), IMetadataProvider(address(0)));
        Party atomicParty = atomicManualParty.createPartyWithMetadata(
            partyImpl,
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            MetadataProvider(address(0)),
            "",
            partyMembers,
            partyMemberVotingPower,
            authorities
        );

        // Ensure `atomicManualParty` is not an authority after creation
        assertFalse(party.isAuthority(address(atomicManualParty)));
        // Ensure authorities passed are authorities
        assertTrue(atomicParty.isAuthority(authorities[0]));
        assertTrue(atomicParty.isAuthority(authorities[1]));

        assertEq(atomicParty.getGovernanceValues().totalVotingPower, 180);

        // Ensure holders match input
        assertEq(atomicParty.getVotingPowerAt(john, uint40(block.timestamp), 0), 100);
        assertEq(atomicParty.getVotingPowerAt(danny, uint40(block.timestamp), 0), 80);
    }
}
