// SPDX-License-Identifier: GPL-3.0
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

    function fooFails() external pure returns (uint256) {
        revert("oopsie");
    }
}

contract TestContract is ReadOnlyDelegateCall {
    uint256 private _retVal;

    function setRetVal(uint256 retVal) external {
        _retVal = retVal;
    }

    function readOnlyDelegateCall(address impl, bytes memory callData) external view {
        _readOnlyDelegateCall(impl, callData);
        assert(false);
    }
}

interface ICallReadOnlyDelegateCall {
    function readOnlyDelegateCall(
        address impl,
        bytes memory callData
    ) external view returns (uint256);
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
        vm.expectRevert();
        ICallReadOnlyDelegateCall(address(testContract)).readOnlyDelegateCall(
            address(impl),
            abi.encodeCall(TestImpl.fooWrites, ())
        );
    }

    function test_propagatesReverts() external {
        uint256 expectedResult = _randomUint256();
        testContract.setRetVal(expectedResult);
        vm.expectRevert("oopsie");
        ICallReadOnlyDelegateCall(address(testContract)).readOnlyDelegateCall(
            address(impl),
            abi.encodeCall(TestImpl.fooFails, ())
        );
    }
}
