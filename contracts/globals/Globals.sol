// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./IGlobals.sol";

// Contract storing global configuration values.
contract Globals is IGlobals {
    address public multiSig;
    // key -> word value
    mapping(uint256 => bytes32) private _wordValues;
    // key -> word value -> isIncluded
    mapping(uint256 => mapping(bytes32 => bool)) private _includedWordValues;

    error OnlyMultiSigError();

    modifier onlyMultisig() {
        if (msg.sender != multiSig) {
            revert OnlyMultiSigError();
        }
        _;
    }

    constructor(address multiSig_) {
        multiSig = multiSig_;
    }

    function transferMultiSig(address newMultiSig) external onlyMultisig {
        multiSig = newMultiSig;
    }

    function getBytes32(uint256 key) external view returns (bytes32) {
        return _wordValues[key];
    }

    function getUint256(uint256 key) external view returns (uint256) {
        return uint256(_wordValues[key]);
    }

    function getAddress(uint256 key) external view returns (address) {
        return address(uint160(uint256(_wordValues[key])));
    }

    function getIncludesBytes32(uint256 key, bytes32 value) external view returns (bool) {
        return _includedWordValues[key][value];
    }

    function getIncludesUint256(uint256 key, uint256 value) external view returns (bool) {
        return _includedWordValues[key][bytes32(value)];
    }

    function getIncludesAddress(uint256 key, address value) external view returns (bool) {
        return _includedWordValues[key][bytes32(uint256(uint160(value)))];
    }

    function setBytes32(uint256 key, bytes32 value) external onlyMultisig {
        _wordValues[key] = value;
    }

    function getImplementation(uint256 key) external view returns (Implementation) {
        return Implementation(address(uint160(uint256(_wordValues[key]))));
    }

    function setUint256(uint256 key, uint256 value) external onlyMultisig {
        _wordValues[key] = bytes32(value);
    }

    function setAddress(uint256 key, address value) external onlyMultisig {
        _wordValues[key] = bytes32(uint256(uint160(value)));
    }

    function setIncludesBytes32(uint256 key, bytes32 value, bool isIncluded) external onlyMultisig {
        _includedWordValues[key][value] = isIncluded;
    }

    function setIncludesUint256(uint256 key, uint256 value, bool isIncluded) external onlyMultisig {
        _includedWordValues[key][bytes32(value)] = isIncluded;
    }

    function setIncludesAddress(uint256 key, address value, bool isIncluded) external onlyMultisig {
        _includedWordValues[key][bytes32(uint256(uint160(value)))] = isIncluded;
    }
}
