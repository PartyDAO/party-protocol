// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

/// @notice Performs operations on behalf of parties.
interface IOperator {
    /// @notice Executes an operation.
    /// @param operatorData Data to be used by the operator, known at the time
    ///                     operation was proposed.
    /// @param executionData Data to be used by the execution, known at the time
    ///                      operation was executed.
    /// @param executor The address that executed the operation.
    /// @param allowOperatorsToSpendPartyEth Whether operators are allowed to
    ///                                      spend party's ETH balance.
    function execute(
        bytes memory operatorData,
        bytes memory executionData,
        address executor,
        bool allowOperatorsToSpendPartyEth
    ) external payable;
}
