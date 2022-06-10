// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../utils/Implementation.sol";
import "../utils/LibRawResult.sol";
import "../utils/ReentrancyGuard.sol";
import "../globals/IGlobals.sol";

import "./IProposalExecutionEngine.sol";
import "./ListOnOpenSeaProposal.sol";
import "./ListOnZoraProposal.sol";
import "./FractionalizeProposal.sol";
import "./ArbitraryCallsProposal.sol";
import "./LibProposal.sol";
import "./ProposalStorage.sol";

contract ProposalExecutionEngine is
    IProposalExecutionEngine,
    Implementation,
    ReentrancyGuard,
    ProposalStorage,
    ListOnOpenSeaProposal,
    FractionalizeProposal,
    ArbitraryCallsProposal
{
    using LibRawResult for bytes;

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
        UpgradeProposalEngineImpl,
        NumProposalTypes
    }

    struct Storage {
        // Given a proposal ID, this maps to the hash of the progress data
        // for the next call to executeProposal().
        // The hash will be 0x0 if the proposal has not been executed.
        // The hash will be of the next progressData to be passed
        // into executeProposal}() if the proposal is in progress.
        // The hash will be of the empty bytes (hex"") if the proposal
        // is completed.
        mapping (bytes32 => bytes32) proposalProgressDataHashByProposalId;
        // The proposal ID of the current, in progress proposal being executed.
        // InProgress proposals need to have executeProposal() called on them
        // multiple times until they complete. Only one proposal may be
        // in progress at a time, meaning no other proposals can be executed
        // if this value is nonzero.
        bytes32 currentInProgressProposalId;
    }

    event ProposalExecutionProgress(bytes32 proposalId, bytes progressData);
    event ProposalEngineImplementationUpgraded(address oldImpl, address newImpl);

    error ZeroProposalIdError();
    error MalformedProposalDataError();
    error ProposalAlreadyCompleteError(bytes32 proposalId);
    error ProposalExecutionBlockedError(bytes32 proposalId, bytes32 currentInProgressProposalId);
    error ProposalProgressDataInvalidError(bytes32 actualProgressDataHash, bytes32 expectedProgressDataHash);

    bytes32 private constant EMPTY_HASH = keccak256("");
    IGlobals private immutable _GLOBALS;
    // Storage slot for `Storage`.
    uint256 private immutable _STORAGE_SLOT;

    constructor(
        IGlobals globals,
        SharedWyvernV2Maker sharedWyvernMaker,
        IZoraAuctionHouse zoraAuctionHouse
    )
        ListOnOpenSeaProposal(globals, sharedWyvernMaker, zoraAuctionHouse)
    {
        _GLOBALS = globals;
        // First version is just the hash of the runtime code. Later versions
        // might hardcode this value if they intend to reuse storage.
        _STORAGE_SLOT = uint256(keccak256('ProposalExecutionEngine.Storage'));
    }

    function initialize(address oldImpl, bytes calldata initializeData)
        external
        override
        onlyDelegateCall
    { /* NOOP */ }

    function getProposalExecutionStatus(bytes32 proposalId)
        external
        view
        returns (ProposalExecutionStatus)
    {
        return _getProposalExecutionStatus(
            _getStorage().proposalProgressDataHashByProposalId[proposalId]
        );
    }

    function getCurrentInProgressProposalId()
        external
        view
        returns (bytes32 id)
    {
        return _getStorage().currentInProgressProposalId;
    }

    // Execute a proposal. Returns the execution status of the proposal.
    function executeProposal(ExecuteProposalParams memory params)
        external
        nonReentrant
        returns (ProposalExecutionStatus status)
    {
        Storage storage stor = _getStorage();
        // Must have a valid proposal ID.
        if (params.proposalId == bytes32(0)) {
            revert ZeroProposalIdError();
        }
        {
            bytes32 nextProgressDataHash =
                stor.proposalProgressDataHashByProposalId[params.proposalId];
             {
                 bytes32 progressDataHash = keccak256(params.progressData);
                 // Progress data must match the one stored.
                 if (nextProgressDataHash != 0 &&
                     nextProgressDataHash != progressDataHash)
                 {
                     revert ProposalProgressDataInvalidError(
                         progressDataHash,
                         nextProgressDataHash
                     );
                 }
            }
            status = _getProposalExecutionStatus(nextProgressDataHash);
            // Proposal must not be completed.
            if (status == ProposalExecutionStatus.Complete) {
                revert ProposalAlreadyCompleteError(params.proposalId);
            }
        }
        // Only one proposal can be in progress at a time.
        bytes32 currentInProgressProposalId = stor.currentInProgressProposalId;
        if (currentInProgressProposalId != bytes32(0)) {
            if (currentInProgressProposalId != params.proposalId) {
                revert ProposalExecutionBlockedError(
                    params.proposalId,
                    currentInProgressProposalId
                );
            }
        }
        stor.currentInProgressProposalId = params.proposalId;

        // Execute the proposal.
        ProposalType pt;
        (pt, params.proposalData) = _getProposalType(params.proposalData);
        bytes memory nextProgressData = _execute(pt, params);
        emit ProposalExecutionProgress(params.proposalId, nextProgressData);

        // Remember the next progress data.
        stor.proposalProgressDataHashByProposalId[params.proposalId] =
            keccak256(nextProgressData);

        // If progress data is empty, the propsal is complete,
        // so clear the current in progress proposal.
        if (nextProgressData.length == 0) {
            stor.currentInProgressProposalId = bytes32(0);
            return ProposalExecutionStatus.Complete;
        }
        return ProposalExecutionStatus.InProgress;
    }

    function _execute(ProposalType pt, ExecuteProposalParams memory params)
        internal
        virtual
        returns (bytes memory progressData)
    {
        if (pt == ProposalType.ListOnOpenSea) {
            progressData = _executeListOnOpenSea(params);
        } else if (pt == ProposalType.ListOnZora) {
            _executeListOnZora(params);
        } else if (pt == ProposalType.Fractionalize) {
            _executeFractionalize(params);
        } else if (pt == ProposalType.ArbitraryCalls) {
            _executeArbitraryCalls(params);
        } else if (pt == ProposalType.UpgradeProposalEngineImpl) {
            _executeUpgradeProposalsImplementation(params.proposalData);
        } else {
            revert UnsupportedProposalTypeError(uint32(pt));
        }
    }

    // Destructively pops off the first 4 bytes of proposalData to determine
    // the type. This modifies `proposalData` and returns the updated
    // pointer to it.
    function _getProposalType(bytes memory proposalData)
        private
        pure
        returns (ProposalType proposalType, bytes memory offsetProposalData)
    {
        // First 4 bytes is propsal type.
        if (proposalData.length < 4) {
            revert MalformedProposalDataError();
        }
        assembly {
            proposalType := and(mload(add(proposalData, 4)), 0xffffffff)
            mstore(add(proposalData, 4), sub(mload(proposalData), 4))
            offsetProposalData := add(proposalData, 4)
        }
        require(proposalType != ProposalType.Invalid);
        require(uint8(proposalType) < uint8(ProposalType.NumProposalTypes));
    }

    // Upgrade the implementation of IPartyProposals to the latest version.
    function _executeUpgradeProposalsImplementation(bytes memory proposalData)
        private
    {
        bytes memory initData = abi.decode(proposalData, (bytes));
        // Always upgrade to latest implementation stored in _GLOBALS.
        IProposalExecutionEngine newImpl = IProposalExecutionEngine(
            _GLOBALS.getAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL)
        );
        _initProposalImpl(newImpl, initData);
        emit ProposalEngineImplementationUpgraded(address(IMPL), address(newImpl));
    }

    // Retrieve the explicit storage bucket for the ProposalExecutionEngine logic.
    function _getStorage() private view returns (Storage storage stor) {
        uint256 slot = _STORAGE_SLOT;
        assembly { stor.slot := slot }
    }

    function _getProposalExecutionStatus(
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
        return ProposalExecutionStatus.InProgress;
    }
}
