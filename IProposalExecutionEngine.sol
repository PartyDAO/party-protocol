// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Upgradeable proposals logic contract interface.
interface IProposalExecutionEngine {
    enum ProposalExecutionStatus {
        // A proposal has not been executed yet.
        Unexecuted,
        // A proposal has been executed at least once but still has more steps
        // to go.
        Incomplete,
        // A proposal has been executed at least once and has completed all its
        // steps.
        Complete
    }

    struct ExecuteProposalParams {
        bytes32 proposalId;
        bytes memory proposalData;
        bytes memory progressData;
        uint256 flags;
        IERC721 preciousToken;
        uint256 preciousTokenId;
    }

    function initialize(address oldImpl) external;
    function getProposalExecutionStatus(bytes32 proposalId)
        external
        view
        returns (getProposalExecutionState);
    function executeProposal(ExecuteProposalParams calldata params)
        external returns (bool completed);
}
