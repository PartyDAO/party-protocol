// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "../../contracts/utils/Implementation.sol";
import "../TestUtils.sol";

contract TestableImplementation is Implementation {
    uint256 public initializeCount;

    constructor() {
        initialize();
    }

    function initialize() public onlyConstructor {
        ++initializeCount;
    }
}

contract ReinitializingImplementation is TestableImplementation {
    constructor() {
        // Attempt to call initialize() again by calling back in.
        // This should be a noop call because the contract has no bytecode
        // during construction.
        address(this).call(abi.encodeCall(this.initialize, ()));
    }
}

contract ImplementationTest is Test, TestUtils {
    function test_cannotInitializeOutsideOfConstructor() external {
        TestableImplementation impl = new TestableImplementation();
        vm.expectRevert(abi.encodeWithSelector(Implementation.OnlyConstructorError.selector));
        impl.initialize();
    }

    function test_cannotReenterReinitialize() external {
        ReinitializingImplementation impl = new ReinitializingImplementation();
        assertEq(impl.initializeCount(), 1);
    }
}
