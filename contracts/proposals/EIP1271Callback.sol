// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Implements a configurable a EIP-1271 callback.
contract EIP1271Callback {
    struct EIP1271CallbackStorage {
        bytes32 validSignedHash;
    }

    bytes4 private constant SUCCESS = 0x1626ba7e;

    // Storage slot for `EIP1271CallbackStorage`.
    uint256 private immutable STORAGE_SLOT;

    constructor() {
        // First version is just the hash of the runtime code. Later versions
        // might hardcode this value if they intend to reuse storage.
        STORAGE_SLOT = uint256(keccak256('EIP1271Callback_V1'));
    }

    function isValidSignature(bytes32 hash, bytes memory /* signature */ )
        external
        view
        returns (bytes4)
    {
        // TODO: Gate msg.sender to OS contract?
        // TODO: Check signature?
        require(hash == _getStorage().validSignedHash, 'INVALID_SIGNED_HASH');
        return SUCCESS;
    }

    function _setValidEIP1271Hash(bytes32 validHash) internal {
        _getStorage().validSignedHash = validHash;
    }

    // Retrieve the explicit storage bucket for the ProposalExecutionEngine logic.
    function _getStorage()
        private
        view
        returns (EIP1271CallbackStorage storage stor)
    {
        uint256 slot = STORAGE_SLOT;
        assembly { stor.slot := slot }
    }
}
