// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../utils/LibRawResult.sol";

abstract contract Multicall {
    using LibRawResult for bytes;

    /// @notice Perform multiple delegatecalls on ourselves.
    function multicall(bytes[] calldata multicallData) external {
        for (uint256 i; i < multicallData.length; ++i) {
            (bool s, bytes memory r) = address(this).delegatecall(multicallData[i]);
            if (!s) {
                r.rawRevert();
            }
        }
    }
}
