// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

contract ReentrancyGuard {

    struct ReentrancyGuardStorage {
        bool hasEntered;
    }

    error NoReentrancyError(address caller);

    uint256 private immutable _REENTRANCY_GUARD_STORAGE_SLOT;

    constructor() {
        _REENTRANCY_GUARD_STORAGE_SLOT = uint256(keccak256('ReentrancyGuard'));
    }

    modifier nonReentrant() {
        ReentrancyGuardStorage storage stor = _getGuardStorage();
        if (stor.hasEntered) {
            revert NoReentrancyError(msg.sender);
        }
        stor.hasEntered = true;
        _;
        stor.hasEntered = false;
    }

    function _getGuardStorage()
        private
        view
        returns (ReentrancyGuardStorage storage stor)
    {
        uint256 s = _REENTRANCY_GUARD_STORAGE_SLOT;
        assembly {
            stor.slot := s
        }
    }
}
