// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Single registry of global values controlled by multisig.
// This will primarily be used to store implemetation addresses shared across
// proxy contracts.
interface IGlobals {
    function getAddress(uint256 id) external view returns (address);
    function getUint256(uint256 id) external view returns (uint256);

    function setAddress(uint256 id, address value) external onlyMultisig;
    function setUint256(uint256 id, uint256 value) external onlyMultisig;
}