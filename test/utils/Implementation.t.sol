// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import { Clones } from "openzeppelin/contracts/proxy/Clones.sol";

import "../../contracts/utils/Implementation.sol";
import "../TestUtils.sol";

contract TestableImplementation is Implementation {
    uint256 public initializeCount;

    function initialize() public onlyInitialize {
        ++initializeCount;
    }
}

contract ImplementationTest is Test, TestUtils {
    using Clones for address;

    TestableImplementation impl = new TestableImplementation();

    function test_cannotReinitialize_logicContract() external {
        impl.initialize();
        vm.expectRevert(abi.encodeWithSelector(Implementation.AlreadyInitialized.selector));
        impl.initialize();
    }

    function test_cannotReinitialize_proxyContract() external {
        TestableImplementation proxy = TestableImplementation(address(impl).clone());
        proxy.initialize();
        vm.expectRevert(abi.encodeWithSelector(Implementation.AlreadyInitialized.selector));
        proxy.initialize();
    }

    function test_implIsAliasForImplementation() external {
        assertEq(impl.IMPL(), address(impl));
    }
}
