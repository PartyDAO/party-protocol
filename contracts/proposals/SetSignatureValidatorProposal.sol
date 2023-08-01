// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { IERC1271 } from "openzeppelin/contracts/interfaces/IERC1271.sol";
import { IProposalExecutionEngine } from "./IProposalExecutionEngine.sol";

abstract contract SetSignatureValidatorProposal {
    struct SetSignatureValidatorProposalStorage {
        /// @notice Mapping from signature hash to signature validator for validating ERC1271 signatures.
        mapping(bytes32 => IERC1271) signatureValidators;
    }
    /// @notice Use a constant, non-overlapping slot offset for the `ZoraProposalStorage` bucket
    uint256 private constant _SET_SIGNATURE_VALIDATOR_PROPOSAL_STORAGE_SLOT =
        uint256(keccak256("SetSignatureValidatorProposal.Storage"));

    /// @notice Struct containing data required for this proposal type
    struct SetSignatureValidatorProposalData {
        bytes32 signatureHash;
        IERC1271 signatureValidator;
    }

    /// @notice Emmitted when the signature validator for a hash is updated
    /// @param hash The hash to update the signature validator for
    /// @param signatureValidator The new signature validator for the hash
    event SignatureValidatorSet(bytes32 indexed hash, IERC1271 indexed signatureValidator);

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

        emit SignatureValidatorSet(data.signatureHash, data.signatureValidator);
    }

    function getSignatureValidatorForHash(bytes32 hash) public view returns (IERC1271) {
        return _getSetSignatureValidatorProposalStorage().signatureValidators[hash];
    }

    /// @notice Retrieve the explicit storage bucket for the `SetSignatureValidatorProposal` struct.
    function _getSetSignatureValidatorProposalStorage()
        private
        pure
        returns (SetSignatureValidatorProposalStorage storage stor)
    {
        uint256 slot = _SET_SIGNATURE_VALIDATOR_PROPOSAL_STORAGE_SLOT;
        assembly {
            stor.slot := slot
        }
    }
}
