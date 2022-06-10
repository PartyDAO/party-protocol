// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../contracts/tokens/IERC20.sol";

contract DummyERC20 is IERC20 {
    string public constant name = 'DummyERC20';
    string public constant symbol = 'DUM';
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deal(address owner, uint256 amount) external {
        balanceOf[owner] += amount;
        totalSupply += amount;
        emit Transfer(address(0), owner, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transferFrom(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address owner, address to, uint256 amount) external returns (bool) {
        _transferFrom(owner, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function _transferFrom(address owner, address to, uint256 amount) private {
        if (msg.sender != owner) {
            if (allowance[owner][msg.sender] != type(uint256).max) {
                allowance[owner][msg.sender] -= amount;
            }
        }
        balanceOf[owner] -= amount;
        balanceOf[to] += amount;
        emit Transfer(owner, to, amount);
    }
}
