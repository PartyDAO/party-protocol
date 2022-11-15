// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../contracts/vendor/solmate/ERC20.sol";

contract DummyERC20 is ERC20 {
    constructor() ERC20("DummyERC20", "DUM", 18) {}

    function deal(address owner, uint256 amount) external {
        _mint(owner, amount);
    }
}
