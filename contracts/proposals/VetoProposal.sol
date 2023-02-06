// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../party/Party.sol";

/// @notice A contract that allows members of a party that has this contract as
///         a host to vote to veto a proposal.
contract VetoProposal {
    error NotPartyHostError();
    error ProposalNotActiveError(uint256 proposalId);

    /// @notice Mapping from party to proposal ID to votes to veto the proposal.
    mapping(Party => mapping(uint256 => uint96)) public vetoVotes;

    /// @notice Vote to veto a proposal.
    /// @param party The party to vote on.
    /// @param proposalId The ID of the proposal to veto.
    /// @param snapIndex The index of the snapshot to use for voting power.
    function voteToVeto(Party party, uint256 proposalId, uint256 snapIndex) external {
        uint96 votes = vetoVotes[party][proposalId];

        // No need to perform following check more than once for party
        if (votes == 0) {
            // Check if this contract is a host of the party
            if (!party.isHost(address(this))) revert NotPartyHostError();
        }

        // Check that proposal is active
        (
            PartyGovernance.ProposalStatus proposalStatus,
            PartyGovernance.ProposalStateValues memory proposalValues
        ) = party.getProposalStateInfo(proposalId);
        if (proposalStatus != PartyGovernance.ProposalStatus.Voting)
            revert ProposalNotActiveError(proposalId);

        // Increase the veto vote count
        uint96 votingPower = party.getVotingPowerAt(
            msg.sender,
            proposalValues.proposedTime - 1,
            snapIndex
        );
        uint96 newVotes = votes + votingPower;

        // Check if the vote to veto is passing
        PartyGovernance.GovernanceValues memory governanceValues = party.getGovernanceValues();
        if (
            _areVotesPassing(
                newVotes,
                governanceValues.totalVotingPower,
                governanceValues.passThresholdBps
            )
        ) {
            // If so, veto the proposal and clear the vote count
            party.veto(proposalId);
            delete vetoVotes[party][proposalId];
        } else {
            // If not, update the vote count
            vetoVotes[party][proposalId] = newVotes;
        }
    }

    function _areVotesPassing(
        uint96 voteCount,
        uint96 totalVotingPower,
        uint16 passThresholdBps
    ) private pure returns (bool) {
        return (uint256(voteCount) * 1e4) / uint256(totalVotingPower) >= uint256(passThresholdBps);
    }
}
