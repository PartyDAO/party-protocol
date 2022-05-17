// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

contract TestUtils {
    uint256 private immutable _nonce;

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

    function _randomBytes32() internal view returns (bytes32) {
        bytes memory seed = abi.encode(
            _nonce,
            block.timestamp,
            gasleft()
        );
        return keccak256(seed);
    }

    function _randomUint256() internal view returns (uint256) {
        return uint256(_randomBytes32());
    }

    function _randomAddress() internal view returns (address payable) {
        return payable(address(uint160(_randomUint256())));
    }

    function _randomRange(uint256 lo, uint256 hi) internal view returns (uint256) {
        return lo + (_randomUint256() % (hi - lo));
    }
}
