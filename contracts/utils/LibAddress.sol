// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

library LibAddress {
    error EthTransferFailed(address receiver, bytes errData);

    // Transfer ETH with full gas stipend.
    function transferEth(address payable receiver, uint256 amount) internal {
        if (amount == 0) return;

        (bool s, bytes memory r) = receiver.call{ value: amount }("");
        if (!s) {
            revert EthTransferFailed(receiver, r);
        }
    }
}
