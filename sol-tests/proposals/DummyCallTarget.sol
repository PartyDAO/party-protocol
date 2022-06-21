pragma solidity ^0.8;

contract DummyCallTarget {
    uint256 private _x = 0;

    function getX() external view returns (uint256) {
        return _x;
    }

    function foo(uint256 x) external returns (uint256) {
        return _x += x;
    }
}
