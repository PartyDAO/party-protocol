// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

contract UnlockedWallet {
    function execCall(
        address payable target,
        uint256 value,
        bytes memory data
    ) external returns (bytes memory r) {
        bool s;
        (s, r) = target.call{ value: value }(data);
        if (!s) {
            assembly {
                revert(add(r, 0x20), mload(r))
            }
        }
    }

    receive() external payable {}
}
