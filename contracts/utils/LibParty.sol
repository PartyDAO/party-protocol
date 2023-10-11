// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../tokens/IERC721.sol";

// States a proposal can be in.
enum ProposalStatus {
    // The proposal does not exist.
    Invalid,
    // The proposal has been proposed (via `propose()`), has not been vetoed
    // by a party host, and is within the voting window. Members can vote on
    // the proposal and party hosts can veto the proposal.
    Voting,
    // The proposal has either exceeded its voting window without reaching
    // `passThresholdBps` of votes or was vetoed by a party host.
    Defeated,
    // The proposal reached at least `passThresholdBps` of votes but is still
    // waiting for `executionDelay` to pass before it can be executed. Members
    // can continue to vote on the proposal and party hosts can veto at this time.
    Passed,
    // Same as `Passed` but now `executionDelay` has been satisfied. Any member
    // may execute the proposal via `execute()`, unless `maxExecutableTime`
    // has arrived.
    Ready,
    // The proposal has been executed at least once but has further steps to
    // complete so it needs to be executed again. No other proposals may be
    // executed while a proposal is in the `InProgress` state. No voting or
    // vetoing of the proposal is allowed, however it may be forcibly cancelled
    // via `cancel()` if the `cancelDelay` has passed since being first executed.
    InProgress,
    // The proposal was executed and completed all its steps. No voting or
    // vetoing can occur and it cannot be cancelled nor executed again.
    Complete,
    // The proposal was executed at least once but did not complete before
    // `cancelDelay` seconds passed since the first execute and was forcibly cancelled.
    Cancelled
}

struct GovernanceOpts {
    // Address of initial party hosts.
    address[] hosts;
    // How long people can vote on a proposal.
    uint40 voteDuration;
    // How long to wait after a proposal passes before it can be
    // executed.
    uint40 executionDelay;
    // Minimum ratio of accept votes to consider a proposal passed,
    // in bps, where 10,000 == 100%.
    uint16 passThresholdBps;
    // Total voting power of governance NFTs.
    uint96 totalVotingPower;
    // Fee bps for distributions.
    uint16 feeBps;
    // Fee recipeint for distributions.
    address payable feeRecipient;
}

// A snapshot of voting power for a member.
struct VotingPowerSnapshot {
    // The timestamp when the snapshot was taken.
    uint40 timestamp;
    // Voting power that was delegated to this user by others.
    uint96 delegatedVotingPower;
    // The intrinsic (not delegated from someone else) voting power of this user.
    uint96 intrinsicVotingPower;
    // Whether the user was delegated to another at this snapshot.
    bool isDelegated;
}

// Accounting and state tracking values for a proposal.
struct ProposalStateValues {
    // When the proposal was proposed.
    uint40 proposedTime;
    // When the proposal passed the vote.
    uint40 passedTime;
    // When the proposal was first executed.
    uint40 executedTime;
    // When the proposal completed.
    uint40 completedTime;
    // Number of accept votes.
    uint96 votes; // -1 == vetoed
    // Number of total voting power at time proposal created.
    uint96 totalVotingPower;
    /// @notice Number of hosts at time proposal created
    uint8 numHosts;
    /// @notice Number of hosts that accepted proposal
    uint8 numHostsAccepted;
}

// Storage states for a proposal.
struct ProposalState {
    // Accounting and state tracking values.
    ProposalStateValues values;
    // Hash of the proposal.
    bytes32 hash;
    // Whether a member has voted for (accepted) this proposal already.
    mapping(address => bool) hasVoted;
}

// Proposal details chosen by proposer.
struct Proposal {
    // Time beyond which the proposal can no longer be executed.
    // If the proposal has already been executed, and is still InProgress,
    // this value is ignored.
    uint40 maxExecutableTime;
    // The minimum seconds this proposal can remain in the InProgress status
    // before it can be cancelled.
    uint40 cancelDelay;
    // Encoded proposal data. The first 4 bytes are the proposal type, followed
    // by encoded proposal args specific to the proposal type. See
    // ProposalExecutionEngine for details.
    bytes proposalData;
}

library LibParty {
    error BadProposalHashError(bytes32 proposalHash, bytes32 actualHash);

    /// @notice Get the hash of a proposal.
    /// @dev Proposal details are not stored on-chain so the hash is used to enforce
    ///      consistency between calls.
    /// @param proposal The proposal to hash.
    /// @return proposalHash The hash of the proposal.
    function getProposalHash(
        Proposal memory proposal
    ) external pure returns (bytes32 proposalHash) {
        // Hash the proposal in-place. Equivalent to:
        // keccak256(abi.encode(
        //   proposal.maxExecutableTime,
        //   proposal.cancelDelay,
        //   keccak256(proposal.proposalData)
        // ))
        bytes32 dataHash = keccak256(proposal.proposalData);
        assembly {
            // Overwrite the data field with the hash of its contents and then
            // hash the struct.
            let dataPos := add(proposal, 0x40)
            let t := mload(dataPos)
            mstore(dataPos, dataHash)
            proposalHash := keccak256(proposal, 0x60)
            // Restore the data field.
            mstore(dataPos, t)
        }
    }

    function isUnanimousVotes(
        uint96 totalVotes,
        uint96 totalVotingPower
    ) external pure returns (bool) {
        uint256 acceptanceRatio = (totalVotes * 1e4) / totalVotingPower;
        // If >= 99.99% acceptance, consider it unanimous.
        // The minting formula for voting power is a bit lossy, so we check
        // for slightly less than 100%.
        return acceptanceRatio >= 0.9999e4;
    }

    function hostsAccepted(
        uint8 snapshotNumHosts,
        uint8 numHostsAccepted
    ) external pure returns (bool) {
        return snapshotNumHosts > 0 && snapshotNumHosts == numHostsAccepted;
    }

    function areVotesPassing(
        uint96 voteCount,
        uint96 totalVotingPower,
        uint16 passThresholdBps
    ) external pure returns (bool) {
        return (uint256(voteCount) * 1e4) / uint256(totalVotingPower) >= uint256(passThresholdBps);
    }

    function hashPreciousList(
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) external pure returns (bytes32 h) {
        assembly {
            mstore(0x00, keccak256(add(preciousTokens, 0x20), mul(mload(preciousTokens), 0x20)))
            mstore(0x20, keccak256(add(preciousTokenIds, 0x20), mul(mload(preciousTokenIds), 0x20)))
            h := keccak256(0x00, 0x40)
        }
    }

    // Assert that the hash of a proposal matches expectedHash.
    function validateProposalHash(Proposal memory proposal, bytes32 expectedHash) external pure {
        // Hash the proposal in-place. Equivalent to:
        // keccak256(abi.encode(
        //   proposal.maxExecutableTime,
        //   proposal.cancelDelay,
        //   keccak256(proposal.proposalData)
        // ))
        bytes32 dataHash = keccak256(proposal.proposalData);
        bytes32 actualHash;
        assembly {
            // Overwrite the data field with the hash of its contents and then
            // hash the struct.
            let dataPos := add(proposal, 0x40)
            let t := mload(dataPos)
            mstore(dataPos, dataHash)
            actualHash := keccak256(proposal, 0x60)
            // Restore the data field.
            mstore(dataPos, t)
        }
        if (expectedHash != actualHash) {
            revert BadProposalHashError(actualHash, expectedHash);
        }
    }
}
