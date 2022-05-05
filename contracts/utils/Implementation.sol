// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Base contract for all contracts intended to be delegatecalled into.
abstract contract Implementation {
    address public immutable IMPL;

    constructor() { IMPL = address(this); }

    modifier onlyDelegateCall() internal {
        require(address(this) != IMPL);
        _;
    }

    // Delegatecalled once when a proxy is deployed.
    function initialize(bytes calldata initializeData)
        external
        abstract;
}
