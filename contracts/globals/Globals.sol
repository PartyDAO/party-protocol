// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./IGlobals.sol";

// Contract storing global configuration values.
contract Globals is IGlobals {
    address public multiSig;
    // key -> word value
    mapping(uint256 => bytes32) private _wordValues;

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

    function getBytes32(uint256 key) public view returns (bytes32) {
        return _wordValues[key];
    }

    function getUint256(uint256 key) public view returns (uint256) {
        return uint256(_wordValues[key]);
    }

    function getAddress(uint256 key) public view returns (address) {
        return address(uint160(uint256(_wordValues[key])));
    }

    function getImplementation(uint256 key) public view returns (Implementation) {
        return Implementation(address(uint160(uint256(_wordValues[key]))));
    }

    function getIncludesUint256(uint256 key, uint256 value) external view returns (bool) {
        uint256 k = uint256(keccak256(abi.encode(key, value)));
        return getUint256(k) != 0;
    }

    function getIncludesBytes32(uint256 key, bytes32 value) external view returns (bool) {
        uint256 k = uint256(keccak256(abi.encode(key, value)));
        return getBytes32(k) != bytes32(0);
    }

    function getIncludesAddress(uint256 key, address value) external view returns (bool) {
        uint256 k = uint256(keccak256(abi.encode(key, value)));
        return getAddress(k) != address(0);
    }

    function setBytes32(uint256 key, bytes32 value) public onlyMultisig {
        _wordValues[key] = value;
    }

    function setUint256(uint256 key, uint256 value) public onlyMultisig {
        _wordValues[key] = bytes32(value);
    }

    function setAddress(uint256 key, address value) public onlyMultisig {
        _wordValues[key] = bytes32(uint256(uint160(value)));
    }

    function setIncludesUint256(uint256 key, uint256 value, bool isIncluded) external {
        uint256 k = uint256(keccak256(abi.encode(key, value)));
        setUint256(k, isIncluded ? 1 : 0);
    }

    function setIncludesBytes32(uint256 key, bytes32 value, bool isIncluded) external {
        bytes32 h = keccak256(abi.encode(key, value));
        uint256 k = uint256(h);
        setBytes32(k, isIncluded ? h : bytes32(0));
    }

    function setIncludesAddress(uint256 key, address value, bool isIncluded) external {
        uint256 k = uint256(keccak256(abi.encode(key, value)));
        setAddress(k, isIncluded ? address(1) : address(0));
    }
}
