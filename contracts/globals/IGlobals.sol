// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../utils/Implementation.sol";

// Single registry of global values controlled by multisig.
// See `LibGlobals` for all valid keys.
interface IGlobals {
    function multiSig() external view returns (address);

    function getBytes32(uint256 key) external view returns (bytes32);

    function getUint256(uint256 key) external view returns (uint256);

    function getBool(uint256 key) external view returns (bool);

    function getAddress(uint256 key) external view returns (address);

    function getImplementation(uint256 key) external view returns (Implementation);

    function getIncludesBytes32(uint256 key, bytes32 value) external view returns (bool);

    function getIncludesUint256(uint256 key, uint256 value) external view returns (bool);

    function getIncludesAddress(uint256 key, address value) external view returns (bool);

    function setBytes32(uint256 key, bytes32 value) external;

    function setUint256(uint256 key, uint256 value) external;

    function setBool(uint256 key, bool value) external;

    function setAddress(uint256 key, address value) external;

    function setIncludesBytes32(uint256 key, bytes32 value, bool isIncluded) external;

    function setIncludesUint256(uint256 key, uint256 value, bool isIncluded) external;

    function setIncludesAddress(uint256 key, address value, bool isIncluded) external;
}
