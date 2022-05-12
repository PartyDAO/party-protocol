// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "./IGlobals.sol";

// TODO: create2 upgradeable? 😉
contract Globals is IGlobals {
    address public immutable MULTISIG;
    mapping(bytes32 => bytes32) private _wordValues;

    modifier onlyMultisig() {
        require(msg.sender == MULTISIG);
        _;
    }

    constructor(address multiSig) {
        MULTISIG = multiSig;
    }

    function getAddress(uint256 id) external view returns (address) {
        return address(uint160(uint256(_wordValues[id])));
    }

    function getUint256(uint256 id) external view returns (uint256) {
        return uint256(_wordValues[id]);
    }

    function setAddress(uint256 id, address value) external onlyMultisig {
        _wordValues[id] = bytes32(uint256(uint160(value)));
    }

    function setUint256(uint256 id, uint256 value) external onlyMultisig {
        _wordValues[id] = uint256(uint160(value));
    }
}
