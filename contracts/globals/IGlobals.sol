// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Single registry of global values controlled by multisig.
// See `LibGlobals` for all valid keys.
interface IGlobals {
    function getAddress(uint256 id) external view returns (address);
    function getUint256(uint256 id) external view returns (uint256);

    function setAddress(uint256 id, address value) external;
    function setUint256(uint256 id, uint256 value) external;
}
