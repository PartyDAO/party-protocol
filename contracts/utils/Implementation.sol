// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

// Base contract for all contracts intended to be delegatecalled into.
abstract contract Implementation {
    event Initialized();

    error AlreadyInitialized();
    error OnlyDelegateCallError();

    /// @notice The address of the implementation contract.
    address public immutable implementation;

    /// @notice Whether or not the implementation has been initialized.
    bool public initialized;

    constructor() {
        implementation = address(this);
    }

    // Reverts if the current function context is not inside of a delegatecall.
    modifier onlyDelegateCall() virtual {
        if (address(this) == implementation) {
            revert OnlyDelegateCallError();
        }
        _;
    }

    modifier onlyInitialize() {
        if (initialized) revert AlreadyInitialized();

        initialized = true;
        emit Initialized();

        _;
    }

    /// @notice The address of the implementation contract.
    /// @dev This is an alias for `implementation` for backwards compatibility.
    function IMPL() external view returns (address) {
        return implementation;
    }
}
