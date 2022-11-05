// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./LibRawResult.sol";
import "./Implementation.sol";

/// @notice Base class for all proxy contracts.
contract Proxy {
    using LibRawResult for bytes;

    /// @notice The address of the implementation contract used by this proxy.
    Implementation public immutable IMPL;

    // Made `payable` to allow initialized crowdfunds to receive ETH as an
    // initial contribution.
    constructor(Implementation impl, bytes memory initCallData) payable {
        IMPL = impl;
        (bool s, bytes memory r) = address(impl).delegatecall(initCallData);
        if (!s) {
            r.rawRevert();
        }
    }

    // Forward all calls to the implementation.
    fallback() external payable {
        Implementation impl = IMPL;
        assembly {
            calldatacopy(0x00, 0x00, calldatasize())
            let s := delegatecall(gas(), impl, 0x00, calldatasize(), 0x00, 0)
            returndatacopy(0x00, 0x00, returndatasize())
            if iszero(s) {
                revert(0x00, returndatasize())
            }
            return(0x00, returndatasize())
        }
    }
}
