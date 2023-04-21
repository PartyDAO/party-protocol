// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../utils/Implementation.sol";
import "../utils/LibRawResult.sol";
import "../globals/IGlobals.sol";

import "./IProposalExecutionEngine.sol";
import "./ListOnOpenseaProposal.sol";
import "./ListOnOpenseaAdvancedProposal.sol";
import "./ListOnZoraProposal.sol";
import "./FractionalizeProposal.sol";
import "./ArbitraryCallsProposal.sol";
import "./ProposalStorage.sol";

/// @notice Upgradable implementation of proposal execution logic for parties that use it.
/// @dev This contract will be delegatecall'ed into by `Party` proxy instances.
contract ProposalExecutionEngine is
    IProposalExecutionEngine,
    Implementation,
    ProposalStorage,
    ListOnOpenseaProposal,
    ListOnOpenseaAdvancedProposal,
    ListOnZoraProposal,
    FractionalizeProposal,
    ArbitraryCallsProposal
{
    using LibRawResult for bytes;

    error UnsupportedProposalTypeError(uint32 proposalType);

    // The types of proposals supported.
    // The first 4 bytes of a proposal's `proposalData` determine the proposal
    // type.
    // WARNING: This should be append-only.
    enum ProposalType {
        Invalid,
        ListOnOpensea,
        ListOnZora,
        Fractionalize,
        ArbitraryCalls,
        UpgradeProposalEngineImpl,
        ListOnOpenseaAdvanced
    }

    // Explicit storage bucket for "private" state owned by the `ProposalExecutionEngine`.
    // See `_getStorage()` for how this is addressed.
    //
    // Read this for more context on the pattern motivating this:
    // https://github.com/dragonfly-xyz/useful-solidity-patterns/tree/main/patterns/explicit-storage-buckets
    struct Storage {
        // The hash of the next `progressData` for the current `InProgress`
        // proposal. This is updated to the hash of the next `progressData` every
        // time a proposal is executed. This enforces that the next call to
        // `executeProposal()` receives the correct `progressData`.
        // If there is no current `InProgress` proposal, this will be 0x0.
        bytes32 nextProgressDataHash;
        // The proposal ID of the current, in progress proposal being executed.
        // `InProgress` proposals need to have `executeProposal()` called on them
        // multiple times until they complete. Only one proposal may be
        // in progress at a time, meaning no other proposals can be executed
        // if this value is nonzero.
        uint256 currentInProgressProposalId;
    }

    event ProposalEngineImplementationUpgraded(address oldImpl, address newImpl);

    error ZeroProposalIdError();
    error MalformedProposalDataError();
    error ProposalExecutionBlockedError(uint256 proposalId, uint256 currentInProgressProposalId);
    error ProposalProgressDataInvalidError(
        bytes32 actualProgressDataHash,
        bytes32 expectedProgressDataHash
    );
    error ProposalNotInProgressError(uint256 proposalId);
    error UnexpectedProposalEngineImplementationError(
        IProposalExecutionEngine actualImpl,
        IProposalExecutionEngine expectedImpl
    );

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;
    // Storage slot for `Storage`.
    // Use a constant, non-overlapping slot offset for the storage bucket.
    uint256 private constant _STORAGE_SLOT = uint256(keccak256("ProposalExecutionEngine.Storage"));

    // Set immutables.
    constructor(
        IGlobals globals,
        IOpenseaExchange seaport,
        IOpenseaConduitController seaportConduitController,
        IZoraAuctionHouse zoraAuctionHouse,
        IFractionalV1VaultFactory fractionalVaultFactory
    )
        ListOnOpenseaAdvancedProposal(globals, seaport, seaportConduitController)
        ListOnZoraProposal(globals, zoraAuctionHouse)
        FractionalizeProposal(fractionalVaultFactory)
        ArbitraryCallsProposal(zoraAuctionHouse)
    {
        _GLOBALS = globals;
    }

    // Used by `Party` to setup the execution engine.
    // Currently does nothing, but may be changed in future versions.
    function initialize(
        address oldImpl,
        bytes calldata initializeData
    ) external override onlyDelegateCall {
        /* NOOP */
    }

    /// @notice Get the current `InProgress` proposal ID.
    /// @dev With this version, only one proposal may be in progress at a time.
    function getCurrentInProgressProposalId() external view returns (uint256 id) {
        return _getStorage().currentInProgressProposalId;
    }

    /// @inheritdoc IProposalExecutionEngine
    function executeProposal(
        ExecuteProposalParams memory params
    ) external onlyDelegateCall returns (bytes memory nextProgressData) {
        // Must have a valid proposal ID.
        if (params.proposalId == 0) {
            revert ZeroProposalIdError();
        }
        Storage storage stor = _getStorage();
        uint256 currentInProgressProposalId = stor.currentInProgressProposalId;
        if (currentInProgressProposalId == 0) {
            // No proposal is currently in progress.
            // Mark this proposal as the one in progress.
            stor.currentInProgressProposalId = params.proposalId;
        } else if (currentInProgressProposalId != params.proposalId) {
            // Only one proposal can be in progress at a time.
            revert ProposalExecutionBlockedError(params.proposalId, currentInProgressProposalId);
        }
        {
            bytes32 nextProgressDataHash = stor.nextProgressDataHash;
            if (nextProgressDataHash == 0) {
                // Expecting no progress data.
                // This is the state if there is no current `InProgress` proposal.
                assert(currentInProgressProposalId == 0);
                if (params.progressData.length != 0) {
                    revert ProposalProgressDataInvalidError(
                        keccak256(params.progressData),
                        nextProgressDataHash
                    );
                }
            } else {
                // Expecting progress data.
                bytes32 progressDataHash = keccak256(params.progressData);
                // Progress data must match the one stored.
                if (nextProgressDataHash != progressDataHash) {
                    revert ProposalProgressDataInvalidError(progressDataHash, nextProgressDataHash);
                }
            }
            // Temporarily set the expected next progress data hash to an
            // unachievable constant to act as a reentrancy guard.
            stor.nextProgressDataHash = bytes32(type(uint256).max);
        }

        // Note that we do not enforce that the proposal has not been executed
        // (and completed) before in this contract. That is enforced by PartyGovernance.

        // Execute the proposal.
        ProposalType pt;
        (pt, params.proposalData) = _extractProposalType(params.proposalData);
        nextProgressData = _execute(pt, params);

        // If progress data is empty, the proposal is complete.
        if (nextProgressData.length == 0) {
            stor.currentInProgressProposalId = 0;
            stor.nextProgressDataHash = 0;
        } else {
            // Remember the next progress data.
            stor.nextProgressDataHash = keccak256(nextProgressData);
        }
    }

    /// @inheritdoc IProposalExecutionEngine
    function cancelProposal(uint256 proposalId) external onlyDelegateCall {
        // Must be a valid proposal ID.
        if (proposalId == 0) {
            revert ZeroProposalIdError();
        }
        Storage storage stor = _getStorage();
        {
            // Must be the current InProgress proposal.
            uint256 currentInProgressProposalId = stor.currentInProgressProposalId;
            if (currentInProgressProposalId != proposalId) {
                revert ProposalNotInProgressError(proposalId);
            }
        }
        // Clear the current InProgress proposal ID and next progress data.
        stor.currentInProgressProposalId = 0;
        stor.nextProgressDataHash = 0;
    }

    // Switch statement used to execute the right proposal.
    function _execute(
        ProposalType pt,
        ExecuteProposalParams memory params
    ) internal virtual returns (bytes memory nextProgressData) {
        if (pt == ProposalType.ListOnOpensea) {
            nextProgressData = _executeListOnOpensea(params);
        } else if (pt == ProposalType.ListOnOpenseaAdvanced) {
            nextProgressData = _executeListOnOpenseaAdvanced(params);
        } else if (pt == ProposalType.ListOnZora) {
            nextProgressData = _executeListOnZora(params);
        } else if (pt == ProposalType.Fractionalize) {
            nextProgressData = _executeFractionalize(params);
        } else if (pt == ProposalType.ArbitraryCalls) {
            nextProgressData = _executeArbitraryCalls(params);
        } else if (pt == ProposalType.UpgradeProposalEngineImpl) {
            _executeUpgradeProposalsImplementation(params.proposalData);
        } else {
            revert UnsupportedProposalTypeError(uint32(pt));
        }
    }

    // Destructively pops off the first 4 bytes of `proposalData` to determine
    // the type. This modifies `proposalData` and returns the updated
    // pointer to it.
    function _extractProposalType(
        bytes memory proposalData
    ) private pure returns (ProposalType proposalType, bytes memory offsetProposalData) {
        // First 4 bytes is proposal type. While the proposal type could be
        // stored in just 1 byte, this makes it easier to encode with
        // `abi.encodeWithSelector`.
        if (proposalData.length < 4) {
            revert MalformedProposalDataError();
        }
        assembly {
            // By reading 4 bytes into the length prefix, the leading 4 bytes
            // of the data will be in the lower bits of the read word.
            proposalType := and(mload(add(proposalData, 4)), 0xffffffff)
            mstore(add(proposalData, 4), sub(mload(proposalData), 4))
            offsetProposalData := add(proposalData, 4)
        }
        require(proposalType != ProposalType.Invalid);
        require(uint8(proposalType) <= uint8(type(ProposalType).max));
    }

    // Upgrade implementation to the latest version.
    function _executeUpgradeProposalsImplementation(bytes memory proposalData) private {
        (address expectedImpl, bytes memory initData) = abi.decode(proposalData, (address, bytes));
        // Always upgrade to latest implementation stored in `_GLOBALS`.
        IProposalExecutionEngine newImpl = IProposalExecutionEngine(
            _GLOBALS.getAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL)
        );
        if (expectedImpl != address(newImpl)) {
            revert UnexpectedProposalEngineImplementationError(
                newImpl,
                IProposalExecutionEngine(expectedImpl)
            );
        }
        _initProposalImpl(newImpl, initData);
        emit ProposalEngineImplementationUpgraded(address(IMPL), expectedImpl);
    }

    // Retrieve the explicit storage bucket for the ProposalExecutionEngine logic.
    function _getStorage() internal pure returns (Storage storage stor) {
        uint256 slot = _STORAGE_SLOT;
        assembly {
            stor.slot := slot
        }
    }
}
