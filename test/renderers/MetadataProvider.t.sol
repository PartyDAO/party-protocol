// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "contracts/renderers/MetadataRegistry.sol";
import "contracts/renderers/MetadataProvider.sol";
import "contracts/globals/Globals.sol";
import "contracts/globals/LibGlobals.sol";
import "forge-std/Test.sol";
import "../TestUtils.sol";

contract MetadataProviderTest is Test, TestUtils {
    event MetadataSet(address indexed instance, bytes metadata);

    address multisig;
    Globals globals;
    MetadataProvider provider;
    MetadataRegistry registry;

    constructor() {
        multisig = _randomAddress();

        globals = new Globals(multisig);
        registry = new MetadataRegistry(globals, new address[](0));
        provider = new MetadataProvider(globals);

        vm.startPrank(multisig);
        globals.setAddress(LibGlobals.GLOBAL_DAO_WALLET, multisig);
        globals.setAddress(LibGlobals.GLOBAL_METADATA_REGISTRY, address(registry));
        vm.stopPrank();
    }

    function test_supportsRegistrars() public {
        assertTrue(provider.supportsRegistrars());
    }

    function test_setMetadata_asInstance() public {
        address instance = _randomAddress();
        bytes memory metadata = "CUSTOM_METADATA";

        vm.prank(instance);
        vm.expectEmit(true, true, true, true);
        emit MetadataSet(instance, metadata);
        provider.setMetadata(instance, metadata);

        assertEq(provider.getMetadata(instance, 0), metadata);
    }

    function test_setMetadata_asRegistrar() public {
        address registrar = _randomAddress();
        address instance = _randomAddress();
        bytes memory metadata = "CUSTOM_METADATA";

        vm.prank(multisig);
        registry.setRegistrar(registrar, instance, true);

        vm.prank(registrar);
        vm.expectEmit(true, true, true, true);
        emit MetadataSet(instance, metadata);
        provider.setMetadata(instance, metadata);

        assertEq(provider.getMetadata(instance, 0), metadata);
    }

    function test_setMetadata_notAuthorized() public {
        address caller = _randomAddress();
        address instance = _randomAddress();
        bytes memory metadata = "CUSTOM_METADATA";

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(MetadataProvider.NotAuthorized.selector, caller, instance)
        );
        provider.setMetadata(instance, metadata);
    }
}
