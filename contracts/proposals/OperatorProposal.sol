// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./IProposalExecutionEngine.sol";
import "../operators/IOperator.sol";

contract OperatorProposal {
    struct OperatorProposalData {
        // Addresses that are allowed to execute the proposal and decide what
        // calldata used by the operator proposal at the time of execution.
        address[] allowedExecutors;
        // The operator contract that will be used to execute the proposal.
        IOperator operator;
        // Amount of ETH to send to the operator contract for executing the proposal.
        uint96 operatorValue;
        // The calldata that will be used by the operator contract to execute the proposal.
        bytes operatorData;
    }

    event OperationExecuted(address executor);

    error NotAllowedToExecute(address executor, address[] allowedExecutors);
    error NotEnoughEthError(uint256 operatorValue, uint256 ethAvailable);

    function _executeOperation(
        IProposalExecutionEngine.ExecuteProposalParams memory params,
        bool allowOperatorsToSpendPartyEth
    ) internal returns (bytes memory nextProgressData) {
        // Decode the proposal data.
        OperatorProposalData memory data = abi.decode(params.proposalData, (OperatorProposalData));
        (uint256 allowedExecutorsIndex, bytes memory executionData) = abi.decode(
            params.extraData,
            (uint256, bytes)
        );

        // Check that the caller is an allowed executor.
        _assertCallerIsAllowedToExecute(msg.sender, data.allowedExecutors, allowedExecutorsIndex);

        // Check whether operator can spend party's ETH balance.
        if (!allowOperatorsToSpendPartyEth && data.operatorValue > msg.value) {
            revert NotEnoughEthError(data.operatorValue, msg.value);
        }

        // Execute the operation.
        data.operator.execute{ value: data.operatorValue }(
            data.operatorData,
            executionData,
            msg.sender,
            allowOperatorsToSpendPartyEth
        );

        // Nothing left to do.
        return "";
    }

    function _assertCallerIsAllowedToExecute(
        address caller,
        address[] memory allowedExecutors,
        uint256 allowedExecutorsIndex
    ) private pure {
        // If there are no allowed executors, then anyone can execute.
        if (allowedExecutors.length == 0) return;

        // Check if the caller is an allowed executor.
        if (caller != allowedExecutors[allowedExecutorsIndex])
            revert NotAllowedToExecute(caller, allowedExecutors);
    }
}
