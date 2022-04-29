// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Base class for all proxy contracts
contract Proxy {
    using LibRawResult for bytes;

    Implementation public immutable IMPL;

    constructor(Implementation impl, bytes calldata initData) payable {
        IMPL = impl;
        (bool s, bytes memory r) = address(impl).delegatecall(
            abi.encodeCall(impl.initialize, initData, msg.sender)
        );
        if (!s) {
            r.rawRevert();
        }
    }

    fallback() external payable {
        // TODO: in asm
        (bool s, bytes memory r) = address(IMPL).delegatecall(msg.data);
        if (!s) {
            r.rawRevert();
        }
        r.rawReturn();
    }
}
