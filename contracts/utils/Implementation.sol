// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

// Base contract for all contracts intended to be delegatecalled into.
abstract contract Implementation {
    error OnlyDelegateCallError();
    error OnlyConstructorError();

    address public immutable IMPL;

    constructor() { IMPL = address(this); }

    // Reverts if the current function context is not inside of a delegatecall.
    modifier onlyDelegateCall() virtual {
        if (address(this) == IMPL) {
            revert OnlyDelegateCallError();
        }
        _;
    }

    // Reverts if the current function context is not inside of a constructor.
    modifier onlyConstructor() {
        uint256 codeSize;
        assembly { codeSize := extcodesize(address()) }
        if (codeSize != 0) {
            revert OnlyConstructorError();
        }
        _;
    }
}
