// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

// Minimal ERC20 interface.
interface IERC20 {
    event Transfer(address indexed owner, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 allowance);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 allowance) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);
}
