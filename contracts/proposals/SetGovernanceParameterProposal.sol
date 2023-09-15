// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { ProposalStorage } from "./ProposalStorage.sol";
import { IProposalExecutionEngine } from "./IProposalExecutionEngine.sol";

contract SetGovernanceParameterProposal is ProposalStorage {
    /// @notice Reverted with when the new governance parameter value is invalid
    error InvalidGovernanceParameter(uint256 value);
    /// @notice Emitted when the execution delay is set
    event ExecutionDelaySet(uint256 oldValue, uint256 newValue);
    /// @notice Emitted when the pass threshold bps is set
    event PassThresholdBpsSet(uint256 oldValue, uint256 newValue);

    /// @notice Enum containing all settable governance parameters
    enum GovernanceParameter {
        ExecutionDelay,
        PassThresholdBps
    }

    /// @notice Struct containing data required for this proposal type
    struct SetGovernanceParameterProposalData {
        GovernanceParameter governanceParameter;
        uint256 newValue;
    }

    /// @notice Execute a `SetGovernanceParameterProposal` which sets the given governance parameter.
    function _executeSetGovernanceParameter(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal returns (bytes memory) {
        SetGovernanceParameterProposalData memory data = abi.decode(
            params.proposalData,
            (SetGovernanceParameterProposalData)
        );

        if (data.governanceParameter == GovernanceParameter.ExecutionDelay) {
            if (data.newValue > 7 days || data.newValue < 1 minutes) {
                revert InvalidGovernanceParameter(data.newValue);
            }
            emit ExecutionDelaySet(
                _getSharedProposalStorage().governanceValues.executionDelay,
                data.newValue
            );
            _getSharedProposalStorage().governanceValues.executionDelay = uint40(data.newValue);
        } else if (data.governanceParameter == GovernanceParameter.PassThresholdBps) {
            if (data.newValue > 10000 || data.newValue < 1000) {
                revert InvalidGovernanceParameter(data.newValue);
            }
            emit PassThresholdBpsSet(
                _getSharedProposalStorage().governanceValues.passThresholdBps,
                data.newValue
            );
            _getSharedProposalStorage().governanceValues.passThresholdBps = uint16(data.newValue);
        }

        return "";
    }
}
