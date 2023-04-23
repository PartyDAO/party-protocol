// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../../contracts/party/PartyFactory.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/proposals/VetoProposal.sol";

import "../TestUtils.sol";

contract VetoProposalTest is Test, TestUtils {
    VetoProposal vetoProposal = new VetoProposal();
    Globals globals = new Globals(address(this));
    Party partyImpl = new Party(globals);
    PartyFactory partyFactory = new PartyFactory(globals);

    Party party;
    Party invalidParty = Party(payable(address(new InvalidParty())));
    uint256 proposalId;

    address voter1;
    address voter2;
    address voter3;

    constructor() {
        voter1 = _randomAddress();
        voter2 = _randomAddress();
        voter3 = _randomAddress();

        globals.setAddress(LibGlobals.GLOBAL_PARTY_IMPL, address(partyImpl));

        address authority = address(this);
        IERC721[] memory preciousTokens = new IERC721[](0);
        uint256[] memory preciousTokenIds = new uint256[](0);
        Party.PartyOptions memory opts = Party.PartyOptions({
            governance: PartyGovernance.GovernanceOpts({
                hosts: _toAddressArray(address(vetoProposal)),
                voteDuration: 3 days,
                executionDelay: 1 days,
                passThresholdBps: 5100,
                totalVotingPower: 3e18,
                feeBps: 0,
                feeRecipient: payable(address(0))
            }),
            name: "Party",
            symbol: "PRTY",
            customizationPresetId: 0
        });
        party = partyFactory.createParty(authority, opts, preciousTokens, preciousTokenIds);

        // Mint voters voting power
        party.mint(voter1, 1e18, voter1);
        party.mint(voter2, 1e18, voter2);
        party.mint(voter3, 1e18, voter3);

        // Create proposal
        PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
            maxExecutableTime: type(uint40).max,
            cancelDelay: 0,
            proposalData: abi.encodePacked([0])
        });
        vm.prank(voter1);
        skip(1);
        proposalId = party.propose(proposal, 0);
    }

    function _assertProposalStatus(PartyGovernance.ProposalStatus expectedStatus) private {
        (PartyGovernance.ProposalStatus status, ) = party.getProposalStateInfo(proposalId);
        assertTrue(status == expectedStatus);
    }

    function test_happyPath() public {
        _assertProposalStatus(PartyGovernance.ProposalStatus.Voting);

        // Vote to veto
        vm.prank(voter1);
        vetoProposal.voteToVeto(party, proposalId, 0);

        _assertProposalStatus(PartyGovernance.ProposalStatus.Voting);
        assertEq(vetoProposal.vetoVotes(party, proposalId), 1e18);

        // Vote to veto (passes threshold)
        vm.prank(voter2);
        vetoProposal.voteToVeto(party, proposalId, 0);

        _assertProposalStatus(PartyGovernance.ProposalStatus.Defeated);
        assertEq(vetoProposal.vetoVotes(party, proposalId), 0); // Cleared after proposal is vetoed
    }

    function test_cannotVetoIfWrongProposalStatus() public {
        // Vote to veto a proposal that does not exist
        vm.prank(voter1);
        vm.expectRevert(
            abi.encodeWithSelector(VetoProposal.ProposalNotActiveError.selector, proposalId + 1)
        );
        vetoProposal.voteToVeto(party, proposalId + 1, 0);
    }

    function test_cannotVetoIfNotHost() public {
        // Vote to veto a proposal where VetoProposal is not a host
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(VetoProposal.NotPartyHostError.selector));
        vetoProposal.voteToVeto(invalidParty, proposalId, 1);
    }

    function test_cannotVetoTwice() public {
        // Vote to veto
        vm.prank(voter1);
        vetoProposal.voteToVeto(party, proposalId, 0);

        // Vote to veto again
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(VetoProposal.AlreadyVotedError.selector));
        vetoProposal.voteToVeto(party, proposalId, 0);
    }
}

contract InvalidParty {
    function isHost(address) public pure returns (bool) {
        return false;
    }
}
