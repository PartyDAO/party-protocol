// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Base class for all proxy contracts
contract Proxy {
    Implementation public immutable IMPL;

    constructor(Implementation impl, bytes calldata initData) {
        IMPL = impl;
        (bool s, bytes memory r) = address(impl).delegatecall(
            abi.encodeCall(impl.initialize, initData)
        );
        if (!s) {
            assembly { revert(add(r, 32), mload(r)) }
        }
    }

    fallback() external payable {
        // but in asm
        (bool s, bytes memory r) = address(IMPL).delegatecall(msg.data);
        if (!s) {
            assembly { revert(add(r, 32), mload(r)) }
        }
        assembly { return(add(r, 32), mload(r)) }
    }
}