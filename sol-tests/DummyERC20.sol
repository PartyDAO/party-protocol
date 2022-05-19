// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "solmate/tokens/ERC20.sol";
import "../contracts/tokens/IERC20.sol";

contract DummyERC20 is ERC20("DummyERC20", "DUM", 18) {
  function deal(address user, uint256 amount) public {
    _mint(user, amount);
  }
}
