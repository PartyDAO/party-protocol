// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { IERC1271 } from "openzeppelin/contracts/interfaces/IERC1271.sol";
import { ProposalStorage } from "./ProposalStorage.sol";
import { IProposalExecutionEngine } from "./IProposalExecutionEngine.sol";

abstract contract SetSignatureValidatorProposal is ProposalStorage {
    struct SetSignatureValidatorProposalStorage {
        /// @notice Mapping from signature hash to signature validator for validating ERC1271 signatures.
        mapping(bytes32 => IERC1271) signatureValidators;
    }
    /// @notice Use a constant, non-overlapping slot offset for the `ZoraProposalStorage` bucket
    uint256 private constant _SET_SIGNATURE_VALIDATOR_PROPOSAL_STORAGE_SLOT =
        uint256(keccak256("SetSignatureValidatorProposal.Storage"));
    struct SetSignatureValidatorProposalData {
        bytes32 signatureHash;
        IERC1271 signatureValidator;
    }

    /// @notice Execute a `SetSignatureValidatorProposal` which sets the validator for a given hash.
    function _executeSetSignatureValidator(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal returns (bytes memory nextProgressData) {
        SetSignatureValidatorProposalData memory data = abi.decode(
            params.proposalData,
            (SetSignatureValidatorProposalData)
        );
        _getSetSignatureValidatorProposalStorage().signatureValidators[data.signatureHash] = data
            .signatureValidator;
        nextProgressData = "";
    }

    /// @notice Retrieve the explicit storage bucket for the `SetSignatureValidatorProposal` struct.
    function _getSetSignatureValidatorProposalStorage()
        internal
        pure
        returns (SetSignatureValidatorProposalStorage storage stor)
    {
        uint256 slot = _SET_SIGNATURE_VALIDATOR_PROPOSAL_STORAGE_SLOT;
        assembly {
            stor.slot := slot
        }
    }
}
