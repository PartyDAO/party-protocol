// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { ProposalStorage } from "./ProposalStorage.sol";
import { IProposalExecutionEngine } from "./IProposalExecutionEngine.sol";

contract SetGovernanceParameterProposal is ProposalStorage {
    /// @notice Reverted with when the new governance parameter value is invalid
    error InvalidGovernanceParameter(uint256 value);
    /// @notice Emitted when the vote duration is set
    event VoteDurationSet(uint256 oldValue, uint256 newValue);
    /// @notice Emitted when the execution delay is set
    event ExecutionDelaySet(uint256 oldValue, uint256 newValue);
    /// @notice Emitted when the pass threshold bps is set
    event PassThresholdBpsSet(uint256 oldValue, uint256 newValue);

    /// @notice Struct containing data required for this proposal type
    struct SetGovernanceParameterProposalData {
        uint40 voteDuration;
        uint40 executionDelay;
        uint16 passThresholdBps;
    }

    /// @notice Execute a `SetGovernanceParameterProposal` which sets the given governance parameter.
    function _executeSetGovernanceParameter(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal returns (bytes memory) {
        SetGovernanceParameterProposalData memory proposalData = abi.decode(
            params.proposalData,
            (SetGovernanceParameterProposalData)
        );
        if (proposalData.voteDuration != 0) {
            if (proposalData.voteDuration < 1 hours) {
                revert InvalidGovernanceParameter(proposalData.voteDuration);
            }
            emit VoteDurationSet(
                _getSharedProposalStorage().governanceValues.voteDuration,
                proposalData.voteDuration
            );
            _getSharedProposalStorage().governanceValues.voteDuration = proposalData.voteDuration;
        }
        if (proposalData.executionDelay != 0) {
            if (proposalData.executionDelay > 30 days) {
                revert InvalidGovernanceParameter(proposalData.executionDelay);
            }
            emit ExecutionDelaySet(
                _getSharedProposalStorage().governanceValues.executionDelay,
                proposalData.executionDelay
            );
            _getSharedProposalStorage().governanceValues.executionDelay = proposalData
                .executionDelay;
        }
        if (proposalData.passThresholdBps != 0) {
            if (proposalData.passThresholdBps > 10000) {
                revert InvalidGovernanceParameter(proposalData.passThresholdBps);
            }
            emit PassThresholdBpsSet(
                _getSharedProposalStorage().governanceValues.passThresholdBps,
                proposalData.passThresholdBps
            );
            _getSharedProposalStorage().governanceValues.passThresholdBps = proposalData
                .passThresholdBps;
        }

        return "";
    }
}
