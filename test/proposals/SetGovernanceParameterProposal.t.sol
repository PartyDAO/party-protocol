// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;
import { SetGovernanceParameterProposal } from "../../contracts/proposals/SetGovernanceParameterProposal.sol";
import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { PartyGovernance } from "../../contracts/party/PartyGovernance.sol";
import { ProposalExecutionEngine } from "../../contracts/proposals/ProposalExecutionEngine.sol";

contract SetGovernanceParameterProposalTest is SetupPartyHelper {
    constructor() SetupPartyHelper(false) {}

    event VoteDurationSet(uint256 oldValue, uint256 newValue);
    event ExecutionDelaySet(uint256 oldValue, uint256 newValue);
    event PassThresholdBpsSet(uint256 oldValue, uint256 newValue);

    uint256 oldPassThresholdBps = 1000;
    uint256 oldVoteDuration = 99;
    uint256 oldExecutionDelay = 300;

    function testGovernanceParameterProposal_multiple() public {
        uint16 newPassThresholdBps = 2000;
        uint40 newVoteDuration = 2 hours;
        uint40 newExecutionDelay = 100;
        PartyGovernance.Proposal memory proposal = _createTestProposal(
            newVoteDuration,
            newExecutionDelay,
            newPassThresholdBps
        );

        uint256 proposalId = _proposeAndPassProposal(proposal);

        assertEq(party.getGovernanceValues().passThresholdBps, oldPassThresholdBps);
        assertEq(party.getGovernanceValues().voteDuration, oldVoteDuration);
        assertEq(party.getGovernanceValues().executionDelay, oldExecutionDelay);

        vm.expectEmit(true, true, true, true);
        emit VoteDurationSet(oldVoteDuration, newVoteDuration);
        vm.expectEmit(true, true, true, true);
        emit ExecutionDelaySet(oldExecutionDelay, newExecutionDelay);
        vm.expectEmit(true, true, true, true);
        emit PassThresholdBpsSet(oldPassThresholdBps, newPassThresholdBps);
        _executeProposal(proposalId, proposal);

        assertEq(party.getGovernanceValues().passThresholdBps, newPassThresholdBps);
        assertEq(party.getGovernanceValues().voteDuration, newVoteDuration);
        assertEq(party.getGovernanceValues().executionDelay, newExecutionDelay);
    }

    function testGovernanceParameterProposal_passThresholdBps() public {
        uint16 newPassThresholdBps = 2000;
        PartyGovernance.Proposal memory proposal = _createTestProposal(0, 0, newPassThresholdBps);

        uint256 proposalId = _proposeAndPassProposal(proposal);

        assertEq(party.getGovernanceValues().passThresholdBps, oldPassThresholdBps);
        vm.expectEmit(true, true, true, true);
        emit PassThresholdBpsSet(oldPassThresholdBps, newPassThresholdBps);
        _executeProposal(proposalId, proposal);

        assertEq(party.getGovernanceValues().passThresholdBps, newPassThresholdBps);
        assertEq(party.getGovernanceValues().voteDuration, oldVoteDuration);
        assertEq(party.getGovernanceValues().executionDelay, oldExecutionDelay);
    }

    function testGovernanceParameterProposal_passThresholdBps_invalid() public {
        PartyGovernance.Proposal memory proposal = _createTestProposal(0, 0, 10001);

        uint256 proposalId = _proposeAndPassProposal(proposal);

        vm.expectRevert(
            abi.encodeWithSelector(
                SetGovernanceParameterProposal.InvalidGovernanceParameter.selector,
                10001
            )
        );
        _executeProposal(proposalId, proposal);
    }

    function testGovernanceParameterProposal_voteDuration() public {
        uint40 newVoteDuration = 2 hours;
        PartyGovernance.Proposal memory proposal = _createTestProposal(newVoteDuration, 0, 0);

        uint256 proposalId = _proposeAndPassProposal(proposal);

        assertEq(party.getGovernanceValues().voteDuration, oldVoteDuration);
        vm.expectEmit(true, true, true, true);
        emit VoteDurationSet(oldVoteDuration, newVoteDuration);
        _executeProposal(proposalId, proposal);

        assertEq(party.getGovernanceValues().voteDuration, newVoteDuration);
        assertEq(party.getGovernanceValues().passThresholdBps, oldPassThresholdBps);
        assertEq(party.getGovernanceValues().executionDelay, oldExecutionDelay);
    }

    function testGovernanceParameterProposal_executionDelay() public {
        uint40 newExecutionDelay = 100;
        PartyGovernance.Proposal memory proposal = _createTestProposal(0, newExecutionDelay, 0);

        uint256 proposalId = _proposeAndPassProposal(proposal);

        assertEq(party.getGovernanceValues().executionDelay, oldExecutionDelay);
        vm.expectEmit(true, true, true, true);
        emit ExecutionDelaySet(oldExecutionDelay, newExecutionDelay);
        _executeProposal(proposalId, proposal);

        assertEq(party.getGovernanceValues().executionDelay, newExecutionDelay);
        assertEq(party.getGovernanceValues().passThresholdBps, oldPassThresholdBps);
        assertEq(party.getGovernanceValues().voteDuration, oldVoteDuration);
    }

    function _createTestProposal(
        uint40 voteDuration,
        uint40 executionDelay,
        uint16 passThresholdBps
    ) private pure returns (PartyGovernance.Proposal memory proposal) {
        SetGovernanceParameterProposal.SetGovernanceParameterProposalData
            memory data = SetGovernanceParameterProposal.SetGovernanceParameterProposalData({
                voteDuration: voteDuration,
                executionDelay: executionDelay,
                passThresholdBps: passThresholdBps
            });
        proposal = PartyGovernance.Proposal({
            maxExecutableTime: type(uint40).max,
            cancelDelay: 0,
            proposalData: abi.encodeWithSelector(
                bytes4(uint32(ProposalExecutionEngine.ProposalType.SetGovernanceParameterProposal)),
                data
            )
        });
    }
}
