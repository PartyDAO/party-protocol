// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "./LibRawResult.sol";

// Performs read-only delegate calls.
contract ReadOnlyDelegateCall {
    using LibRawResult for bytes;

    function delegateCallAndRevert(address impl, bytes memory callData)
        external
    {
        // Attempt to gate to only `_readOnlyDelegateCall()` invocations.
        require(msg.sender == address(this));
        (bool s, bytes memory r) = impl.delegatecall(callData);
        abi.encode(s, r).rawRevert();
    }

    // Perform a delegateCallAndRevert() then return the raw result data.
    function _readOnlyDelegateCall(address impl, bytes memory callData)
        internal
        returns (bool success, bytes memory resultData)
    {
        try this.delegateCallAndRevert(impl, callData) {
            assert(false);
        }
        catch (bytes memory r) {
            (success, resultData) = abi.decode(r, (bool, bytes));
            if (!success) {
                resultData.rawRevert();
            }
            resultData.rawReturn();
        }
    }
}
