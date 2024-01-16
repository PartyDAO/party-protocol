// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./IProposalExecutionEngine.sol";
import "../utils/LibRawResult.sol";

// The storage bucket shared by `PartyGovernance` and the `ProposalExecutionEngine`.
// Read this for more context on the pattern motivating this:
// https://github.com/dragonfly-xyz/useful-solidity-patterns/tree/main/patterns/explicit-storage-buckets
abstract contract ProposalStorage {
    using LibRawResult for bytes;

    struct SharedProposalStorage {
        IProposalExecutionEngine engineImpl;
        ProposalEngineOpts opts;
        GovernanceValues governanceValues;
    }

    /// @notice Governance values stored for a party
    struct GovernanceValues {
        uint40 voteDuration;
        uint40 executionDelay;
        uint16 passThresholdBps;
        uint96 totalVotingPower;
    }

    struct ProposalEngineOpts {
        // Whether the party can add new authorities with the add authority proposal.
        bool enableAddAuthorityProposal;
        // Whether the party can spend ETH from the party's balance with
        // arbitrary call proposals.
        bool allowArbCallsToSpendPartyEth;
        // Whether operators can be used.
        bool allowOperators;
        // Whether distributions require a vote or can be executed by any active member.
        bool distributionsRequireVote;
    }

    uint256 internal constant PROPOSAL_FLAG_UNANIMOUS = 0x1;
    uint256 private constant SHARED_STORAGE_SLOT =
        uint256(keccak256("ProposalStorage.SharedProposalStorage"));

    function _initProposalImpl(IProposalExecutionEngine impl, bytes memory initData) internal {
        SharedProposalStorage storage stor = _getSharedProposalStorage();
        IProposalExecutionEngine oldImpl = stor.engineImpl;
        stor.engineImpl = impl;
        (bool s, bytes memory r) = address(impl).delegatecall(
            abi.encodeCall(IProposalExecutionEngine.initialize, (address(oldImpl), initData))
        );
        if (!s) {
            r.rawRevert();
        }
    }

    function _getSharedProposalStorage()
        internal
        pure
        returns (SharedProposalStorage storage stor)
    {
        uint256 s = SHARED_STORAGE_SLOT;
        assembly {
            stor.slot := s
        }
    }
}
