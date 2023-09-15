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

    function testGovernanceParameterProposal_passThresholdBps_vanilla() public {
        PartyGovernance.Proposal memory proposal = _createTestProposal(
            SetGovernanceParameterProposal.GovernanceParameter.PassThresholdBps,
            2000
        );

        uint256 proposalId = _proposeAndPassProposal(proposal);

        assertEq(party.getGovernanceValues().passThresholdBps, 1000);
        vm.expectEmit(true, true, true, true);
        emit PassThresholdBpsSet(1000, 2000);
        _executeProposal(proposalId, proposal);

        assertEq(party.getGovernanceValues().passThresholdBps, 2000);
    }

    function _createTestProposal(
        SetGovernanceParameterProposal.GovernanceParameter governanceParameter,
        uint256 newValue
    ) private pure returns (PartyGovernance.Proposal memory proposal) {
        SetGovernanceParameterProposal.SetGovernanceParameterProposalData
            memory data = SetGovernanceParameterProposal.SetGovernanceParameterProposalData({
                governanceParameter: governanceParameter,
                newValue: newValue
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
