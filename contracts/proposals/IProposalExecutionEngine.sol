// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../tokens/IERC721.sol";

// Upgradeable proposals logic contract interface.
interface IProposalExecutionEngine {
    enum ProposalExecutionStatus {
        // A proposal has not been executed yet.
        Unexecuted,
        // A proposal has been executed at least once but still has more steps
        // to go.
        InProgress,
        // A proposal has been executed at least once and has completed all its
        // steps.
        Complete
    }

    struct ExecuteProposalParams {
        bytes32 proposalId;
        bytes proposalData;
        bytes progressData;
        uint256 flags;
        IERC721 preciousToken;
        uint256 preciousTokenId;
    }

    function initialize(bytes calldata initData) external;
    function getProposalExecutionStatus(bytes32 proposalId)
        external
        view
        returns (ProposalExecutionStatus);
    function executeProposal(ExecuteProposalParams calldata params)
        external returns (ProposalExecutionStatus);
}
