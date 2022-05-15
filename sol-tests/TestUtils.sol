// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

contract TestUtils {
    uint256 private _nonce;

    constructor() {
        _nonce = uint256(keccak256(abi.encode(
            tx.origin,
            tx.origin.balance,
            block.number,
            block.timestamp,
            block.coinbase
        )));
    }

    modifier skipped() {
        return;
        _;
    }

    modifier onlyForked() {
        if (block.number < 1e6) {
            return;
        }
        _;
    }

    function _randomBytes32() internal returns (bytes32) {
        bytes memory seed = abi.encode(
            block.timestamp,
            _nonce++
        );
        return keccak256(seed);
    }

    function _randomUint256() internal returns (uint256) {
        return uint256(_randomBytes32());
    }

    function _randomAddress() internal returns (address payable) {
        return payable(address(uint160(_randomUint256())));
    }
}
