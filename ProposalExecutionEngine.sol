// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

contract ProposalExecutionEngine is
    IPartyProposals,
    Implementation,
    ListOnOpenSeaProposal,
    ListOnZoraProposal,
    FractionalizeProposal,
    ArbitraryCallsProposal
{
    error UnsupportedProposalTypeError(uint32 proposalType);

    // The types of proposals supported.
    // The first 4 bytes of a proposal's `proposalData` determine the proposal
    // type.
    enum ProposalType {
        Invalid,
        ListOnOpenSea,
        ListOnZora,
        Fractionalize,
        ArbitraryCalls,
        UpgradeProposalImplementation,
        NumProposalTypes
    }

    struct Storage {
        // Given a proposal ID, this maps to the hash of the progress data
        // for the next call to executeProposal().
        // The hash will be 0x0 if the proposal has not been executed.
        // The hash will be of the next progressData to be passed
        // into executeProposal}() if the proposal is incomplete.
        // The hash will be of the empty bytes (hex"") if the proposal
        // is completed.
        mapping (bytes32 => bytes32) proposalProgressDataHashByProposalId;
        // The proposal ID of the current, incomplete proposal being executed.
        // Incomplete proposals need to have executeProposal() called on them
        // multiple times until they complete. Only one proposal may be
        // incomplete at a time, meaning no other proposals can be executed
        // if this value is nonzero.
        bytes32 currentIncompleteProposalId;
    }

    event ProposalExecutionProgress(bytes32 proposalId, bytes progressData);

    bytes32 private constant EMPTY_HASH = keccak256("");
    IGlobals private immutable GLOBALS;
    // Storage slot for `Storage`.
    uint256 private immutable STORAGE_SLOT;

    constructor(IGlobals globals) ListOnOpenSeaProposal(globals) {
        GLOBALS = globals;
        // First version is just the hash of the runtime code. Later versions
        // might hardcode this value if they intend to reuse storage.
        STORAGE_SLOT = keccak256(type(ProposalExecutionEngine).runtimeCode);
    }

    function initialize(bytes calldata initializeData) external { /* NOOP */ }

    function getProposalExecutionStatus(bytes32 proposalId)
        external
        view
        returns (ProposalExecutionStatus)
    {
        return _getProposalExecutionStatus(
            proposalId,
            _getStorage().proposalProgressDataHashByProposalId[proposalId]
        );
    }

    // Execute a proposal. Returns the execution status of the proposal.
    function executeProposal(ExecuteProposalParams calldata params)
        external
        returns (ProposalExecutionStatus status)
    {
        // Must have a valid proposal ID.
        require(params.proposalId != bytes32(0));
        // Proposal must not be completed.
        require(
            _getProposalExecutionStatus(proposalId, progressDataHash)
                != ProposalExecutionStatus.Complete
        );
        Storage storage stor = _getStorage();
        // Only one proposal can be incomplete at a time.
        if (currentIncompleteProposalId != bytes32(0)) {
            bytes32 currentIncompleteProposalId = stor.currentIncompleteProposalId;
            if (currentIncompleteProposalId != params.proposalId) {
                revert ProposalExecutionBlocked(
                    params.proposalId,
                    currentIncompleteProposalId
                );
            }
        }
        stor.currentIncompleteProposalId = params.proposalId;

        // Execute the proposal.
        bytes memory nextProgressData = _execute(params);
        emit ProposalExecutionProgress(proposalId, nextProgressData);

        // Remember the next progress data.
        stor.proposalProgressDataHashByProposalId[proposalInfo] =
            keccak256(nextProgressData);

        // If progress data is empty, the propsal is complete,
        // so clear the current incomplete proposal.
        if (nextProgressData.length == 0) {
            stor.currentIncompleteProposalId = bytes32(0);
            return ProposalExecutionStatus.Complete;
        }
        return ProposalExecutionStatus.Incomplete;
    }

    function _execute(ExecuteProposalParams memory params)
        private
        returns (bytes memory progressData)
    {
        (ProposalType pt, params.proposalData) =
            _getProposalType(params.proposalData);
        bytes memory proposalData = params
        if (pt == ProposalType.ListOnOpenSea) {
            progressData = _executeListOnOpenSea(params);
        if (pt == ProposalType.ListOnZora) {
            _executeListOnZora(params);
        if (pt == ProposalType.Fractionalize) {
            _executeFractionalize(params);
        if (pt == ProposalType.ArbitraryCalls) {
            _executeArbitraryCalls(params);
        } else if (pt == ProposalType.UpgradeProposalImplementation) {
            _executeUpgradeProposalsImplementation();
        } else {
            revert UnsupportedProposalTypeError(uint32(pt));
        }
    }

    // Destructively pops off the first 4 bytes of proposalData to determine
    // the type. This modifies `proposalData` and returns the updated
    // pointer to it.
    function _getProposalType(bytes memory proposalData)
        private
        returns (ProposalType proposalType, bytes memory offsetProposalData)
    {
        // First 4 bytes is propsal type.
        require(proposalData.length >= 4);
        assembly {
            proposalType := and(mload(add(proposalData, 4)), 0xffffffff)
            mstore(add(proposalData, 4), sub(mload(proposalData), 4))
            offsetProposalData := add(proposalData, 4)
        }
        require(proposalType != ProposalType.Invalid);
        require(uint8(proposalType) < uint8(ProposalType.NumProposalTypes));
    }

    // Upgrade the implementation of IPartyProposals to the latest version.
    function _executeUpgradeProposalsImplementation()
        private
    {
        // Always upgrade to latest implementation stored in GLOBALS.
        address newImpl = GLOBALS.getAddress(IGlobals.GLOBAL_PARTY_PROPOSAL_IMPL);
        LibProposal.setProposalsImpl(newImpl);
        (bool s, bytes memory r) = address(newImpl)
            .delegatecall(abi.encodeCall(
                IPartyProposals.initialize,
                abi.encode(IMPL)
            ));
        if (!s) {
            r.rawRevert();
        }
    }

    // Retrieve the explicit storage bucket for the ProposalExecutionEngine logic.
    function _getStorage() private pure returns (Storage storage stor) {
        uint256 slot = STORAGE_SLOT;
        assembly { stor := slot }
    }

    function _getProposalExecutionStatus(
        bytes32 proposalId,
        bytes32 storedProgressDataHash
    )
        private
        pure
        returns (ProposalExecutionStatus)
    {
        if (storedProgressDataHash == EMPTY_HASH) {
            return ProposalExecutionStatus.Complete;
        }
        if (storedProgressDataHash == bytes32(0)) {
            return ProposalExecutionStatus.Unexecuted;
        }
        return ProposalExecutionStatus.Incomplete;
    }
}
