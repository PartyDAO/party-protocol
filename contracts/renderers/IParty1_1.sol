// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

interface IParty1_1 {
    enum ProposalStatus {
        Invalid,
        Voting,
        Defeated,
        Passed,
        Ready,
        InProgress,
        Complete,
        Cancelled
    }

    struct ProposalStateValues {
        uint40 proposedTime;
        uint40 passedTime;
        uint40 executedTime;
        uint40 completedTime;
        uint96 votes;
    }

    function mintAuthority() external view returns (address);

    function getProposalStateInfo(
        uint256 proposalId
    ) external view returns (ProposalStatus status, ProposalStateValues memory values);
}
