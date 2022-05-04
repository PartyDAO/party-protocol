// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Performs read-only delegate calls.
library LibRawResult {
    function rawRevert(bytes memory b)
        internal
        pure
    {
        assembly { revert(add(b, 32), mload(b)) }
    }

    function rawReturn(bytes memory b)
        internal
        pure
    {
        assembly { return(add(b, 32), mload(b)) }
    }
}
