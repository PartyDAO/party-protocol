// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

contract MockParty {
    event MockMint(
        address caller,
        address owner,
        uint256 amount,
        address delegate
    );

    function mint(
        address owner,
        uint256 amount,
        address delegate
    ) external {
        emit MockMint(msg.sender, owner, amount, delegate);
    }
}
