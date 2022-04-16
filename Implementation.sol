// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Base contract for all contracts intended to be delegatecalled into.
abstract contract Implementation {
    address private immutable IMPL;

    constructor() { IMPL = address(this); }

    modifier onlyDelegateCall() internal {
        require(address(this) != IMPL);
        _;
    }

    function initialize(bytes calldata initializeData) external abstract;
}