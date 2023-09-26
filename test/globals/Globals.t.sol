// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "contracts/globals/Globals.sol";
import "../TestUtils.sol";

contract GlobalsTest is TestUtils {
    event ValueSet(uint256 key, bytes32 oldValue, bytes32 newValue);
    event IncludesSet(uint256 key, bytes32 value, bool oldIsIncluded, bool newIsIncluded);
    event PendingMultiSigSet(address indexed oldPendingMultiSig, address indexed pendingMultiSig);
    event MultiSigSet(address indexed oldMultiSig, address indexed newMultiSig);

    Globals globals = new Globals(address(this));

    function test_transferAndAccept_multisig() public {
        address payable newMultisig = _randomAddress();

        vm.expectEmit(true, true, true, true);
        emit PendingMultiSigSet(address(0), newMultisig);
        globals.transferMultiSig(newMultisig);

        assertEq(globals.pendingMultiSig(), newMultisig);
        assertEq(globals.multiSig(), address(this));

        vm.prank(newMultisig);
        vm.expectEmit(true, true, true, true);
        emit MultiSigSet(address(this), newMultisig);
        globals.acceptMultiSig();

        assertEq(globals.multiSig(), newMultisig);
        assertEq(globals.pendingMultiSig(), address(0));
    }

    function test_transferMultisig_notMultisig() public {
        address payable notMultisig = _randomAddress();

        vm.prank(notMultisig);
        vm.expectRevert(Globals.OnlyMultiSigError.selector);
        globals.transferMultiSig(notMultisig);
    }

    function test_acceptMultisig_notPendingMultisig() public {
        address payable notPendingMultisig = _randomAddress();

        vm.prank(notPendingMultisig);
        vm.expectRevert(Globals.OnlyPendingMultiSigError.selector);
        globals.acceptMultiSig();
    }

    function test_setAndGetBytes32_works() public {
        uint256 key = _randomUint256();
        bytes32 value = _randomBytes32();

        assertEq(globals.getBytes32(key), bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit ValueSet(key, bytes32(0), value);
        globals.setBytes32(key, value);

        assertEq(globals.getBytes32(key), value);
    }

    function test_setBytes32_onlyMultisig() public {
        uint256 key = _randomUint256();
        bytes32 value = _randomBytes32();

        vm.prank(_randomAddress());
        vm.expectRevert(Globals.OnlyMultiSigError.selector);
        globals.setBytes32(key, value);
    }

    function test_setAndGetUint256_works() public {
        uint256 key = _randomUint256();
        uint256 value = _randomUint256();

        assertEq(globals.getUint256(key), 0);

        vm.expectEmit(true, true, true, true);
        emit ValueSet(key, bytes32(0), bytes32(value));
        globals.setUint256(key, value);

        assertEq(globals.getUint256(key), value);
    }

    function test_setUint256_onlyMultisig() public {
        uint256 key = _randomUint256();
        uint256 value = _randomUint256();

        vm.prank(_randomAddress());
        vm.expectRevert(Globals.OnlyMultiSigError.selector);
        globals.setUint256(key, value);
    }

    function test_setAndGetBool_works() public {
        uint256 key = _randomUint256();

        assertEq(globals.getBool(key), false);

        vm.expectEmit(true, true, true, true);
        emit ValueSet(key, bytes32(0), bytes32(uint256(1)));
        globals.setBool(key, true);

        assertEq(globals.getBool(key), true);
    }

    function test_setAndGetAddress_works() public {
        uint256 key = _randomUint256();
        address value = _randomAddress();

        assertEq(globals.getAddress(key), address(0));

        vm.expectEmit(true, true, true, true);
        emit ValueSet(key, bytes32(0), bytes32(uint256(uint160(value))));
        globals.setAddress(key, value);

        assertEq(globals.getAddress(key), value);
    }

    function test_setAddress_onlyMultisig() public {
        uint256 key = _randomUint256();
        address value = _randomAddress();

        vm.prank(_randomAddress());
        vm.expectRevert(Globals.OnlyMultiSigError.selector);
        globals.setAddress(key, value);
    }

    function test_setAndGetIncludesBytes32_works() public {
        uint256 key = _randomUint256();
        bytes32 value = _randomBytes32();

        assertEq(globals.getIncludesBytes32(key, value), false);

        vm.expectEmit(true, true, true, true);
        emit IncludesSet(key, value, false, true);
        globals.setIncludesBytes32(key, value, true);

        assertEq(globals.getIncludesBytes32(key, value), true);
    }

    function test_setIncludesBytes32_onlyMultisig() public {
        uint256 key = _randomUint256();
        bytes32 value = _randomBytes32();

        vm.prank(_randomAddress());
        vm.expectRevert(Globals.OnlyMultiSigError.selector);
        globals.setIncludesBytes32(key, value, true);
    }

    function test_setAndGetIncludesUint256_works() public {
        uint256 key = _randomUint256();
        uint256 value = _randomUint256();

        assertEq(globals.getIncludesUint256(key, value), false);

        vm.expectEmit(true, true, true, true);
        emit IncludesSet(key, bytes32(value), false, true);
        globals.setIncludesUint256(key, value, true);

        assertEq(globals.getIncludesUint256(key, value), true);
    }

    function test_setIncludesUint256_onlyMultisig() public {
        uint256 key = _randomUint256();
        uint256 value = _randomUint256();

        vm.prank(_randomAddress());
        vm.expectRevert(Globals.OnlyMultiSigError.selector);
        globals.setIncludesUint256(key, value, true);
    }

    function test_setAndGetIncludesAddress_works() public {
        uint256 key = _randomUint256();
        address value = _randomAddress();

        assertEq(globals.getIncludesAddress(key, value), false);

        vm.expectEmit(true, true, true, true);
        emit IncludesSet(key, bytes32(uint256(uint160(value))), false, true);
        globals.setIncludesAddress(key, value, true);

        assertEq(globals.getIncludesAddress(key, value), true);
    }

    function test_setIncludesAddress_onlyMultisig() public {
        uint256 key = _randomUint256();
        address value = _randomAddress();

        vm.prank(_randomAddress());
        vm.expectRevert(Globals.OnlyMultiSigError.selector);
        globals.setIncludesAddress(key, value, true);
    }
}
