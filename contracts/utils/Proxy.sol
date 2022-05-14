// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./LibRawResult.sol";
import "./Implementation.sol";

// Base class for all proxy contracts
contract Proxy {
    using LibRawResult for bytes;

    Implementation public immutable IMPL;

    constructor(Implementation impl, bytes memory initCallData) payable {
        IMPL = impl;
        (bool s, bytes memory r) = address(impl).delegatecall(initCallData);
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
