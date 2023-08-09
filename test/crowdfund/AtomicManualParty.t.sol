/// SPDX-
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { AtomicManualParty } from "../../contracts/crowdfund/AtomicManualParty.sol";
import { Party } from "../../contracts/party/Party.sol";
import { Proxy } from "../../contracts/utils/Proxy.sol";
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
    event ProviderSet(address indexed instance, IMetadataProvider indexed provider);

    AtomicManualParty private atomicManualParty;

    constructor() SetupPartyHelper(false) {}

    function setUp() public override {
        super.setUp();
        atomicManualParty = new AtomicManualParty(globals, partyFactory);
    }

    function test_createAtomicManualParty() public {
        Party.PartyOptions memory opts;
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.voteDuration = 99;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 180;

        address[] memory partyMembers = new address[](2);
        uint96[] memory partyMemberVotes = new uint96[](2);

        partyMembers[0] = john;
        partyMembers[1] = danny;

        partyMemberVotes[0] = 100;
        partyMemberVotes[1] = 80;

        // Not checking address of the party
        vm.expectEmit(false, true, true, true);
        emit PartyCreated(
            Party(payable(0)),
            opts,
            preciousTokens,
            preciousTokenIds,
            address(atomicManualParty)
        );
        atomicManualParty.createParty(
            Party(payable(address(Proxy(payable(address(party))).IMPL()))),
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            partyMembers,
            partyMemberVotes
        );

        // Ensure `atomicManualParty` is not an authority after creation
        assertFalse(party.isAuthority(address(atomicManualParty)));
    }

    function test_createAtomicManualPartyWithMetadata() public {
        Party.PartyOptions memory opts;
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.voteDuration = 99;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 180;

        address[] memory partyMembers = new address[](2);
        uint96[] memory partyMemberVotes = new uint96[](2);

        partyMembers[0] = john;
        partyMembers[1] = danny;

        partyMemberVotes[0] = 100;
        partyMemberVotes[1] = 80;

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
        atomicManualParty.createPartyWithMetadata(
            Party(payable(address(Proxy(payable(address(party))).IMPL()))),
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            MetadataProvider(address(0)),
            "",
            partyMembers,
            partyMemberVotes
        );

        // Ensure `atomicManualParty` is not an authority after creation
        assertFalse(party.isAuthority(address(atomicManualParty)));
    }

    function test_createAtomicManualPartyArityMismatch() public {
        Party.PartyOptions memory opts;
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.voteDuration = 99;
        opts.governance.executionDelay = _EXECUTION_DELAY;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = 180;

        address[] memory partyMembers = new address[](3);
        uint96[] memory partyMemberVotes = new uint96[](2);

        partyMembers[0] = john;
        partyMembers[1] = danny;
        partyMembers[2] = steve;

        partyMemberVotes[0] = 100;
        partyMemberVotes[1] = 80;

        Party partyImpl = Party(payable(address(Proxy(payable(address(party))).IMPL())));
        vm.expectRevert(AtomicManualParty.PartyMembersArityMismatch.selector);
        atomicManualParty.createParty(
            partyImpl,
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            partyMembers,
            partyMemberVotes
        );
    }
}
