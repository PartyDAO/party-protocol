// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../tokens/IERC721.sol";

// Upgradeable proposals logic contract interface.
interface IProposalExecutionEngine {
    struct ExecuteProposalParams {
        bytes32 proposalId;
        bytes proposalData;
        bytes progressData;
        uint256 flags;
        IERC721[] preciousTokens;
        uint256[] preciousTokenIds;
    }

    function initialize(address oldImpl, bytes memory initData) external;
    /// @notice Execute a proposal.
    /// @dev Must be delegatecalled into by PartyGovernance.
    ///      If the proposal is incomplete, continues its next step (if possible).
    ///      If another proposal is incomplete, this will fail. Only one
    ///      incomplete proposal is allowed at a time.
    /// @return nextProgressData bytes to be passed into the next execute() call,
    ///         if the proposal execution is incomplete. Otherwise, empty bytes
    ///         to indicate the proposal is complete.
    function executeProposal(ExecuteProposalParams memory params)
        external returns (bytes memory nextProgressData);
    /// @notice Forcibly cancel an incomplete proposal.
    /// @dev This is intended to be a last resort as it can leave a party in a
    ///      broken step. Whenever possible, proposals should be allowed to
    ///      complete their entire lifecycle.
    function cancelProposal(bytes32 proposalId) external;
}
