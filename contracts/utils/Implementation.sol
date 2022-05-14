// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

// Base contract for all contracts intended to be delegatecalled into.
abstract contract Implementation {
    address public immutable IMPL;

    constructor() { IMPL = address(this); }

    modifier onlyDelegateCall() {
        require(address(this) != IMPL);
        _;
    }
}
