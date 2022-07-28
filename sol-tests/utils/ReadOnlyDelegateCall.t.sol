// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../contracts/utils/ReadOnlyDelegateCall.sol";
import "../TestUtils.sol";

contract TestImpl {
    uint256 private _retVal;

    function fooReadOnly() external view returns (uint256) {
        return _retVal;
    }

    function fooWrites() external returns (uint256) {
        return _retVal++;
    }
}

contract TestContract is ReadOnlyDelegateCall {
    uint256 private _retVal;

    function setRetVal(uint256 retVal) external {
        _retVal = retVal;
    }

    function readOnlyDelegateCall(address impl, bytes memory callData) external returns (uint256) {
        (bool s, bytes memory r) = _readOnlyDelegateCall(impl, callData);
        require(s, 'failed');
        return abi.decode(r, (uint256));
    }
}

interface ICallReadOnlyDelegateCall {
    function readOnlyDelegateCall(address impl, bytes memory callData) external view returns (uint256);
}

contract ReadOnlyDelegateCallTest is Test, TestUtils {

    TestContract testContract = new TestContract();
    TestImpl impl = new TestImpl();

    function test_canCallReadOnlyFunction() external {
        uint256 expectedResult = _randomUint256();
        testContract.setRetVal(expectedResult);
        uint256 result = ICallReadOnlyDelegateCall(address(testContract)).readOnlyDelegateCall(
            address(impl),
            abi.encodeCall(TestImpl.fooReadOnly, ())
        );
        assertEq(result, expectedResult);
    }

    function test_cannotCallWriteFunction() external {
        uint256 expectedResult = _randomUint256();
        testContract.setRetVal(expectedResult);
        uint256 result = ICallReadOnlyDelegateCall(address(testContract)).readOnlyDelegateCall(
            address(impl),
            abi.encodeCall(TestImpl.fooWrites, ())
        );
        assertEq(result, expectedResult);
    }
}
