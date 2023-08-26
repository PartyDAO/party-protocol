// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "contracts/renderers/MetadataRegistry.sol";
import "contracts/renderers/MetadataProvider.sol";
import "contracts/globals/Globals.sol";
import "contracts/globals/LibGlobals.sol";
import "forge-std/Test.sol";
import "../TestUtils.sol";

contract MetadataRegistryTest is Test, TestUtils {
    event ProviderSet(address indexed instance, IMetadataProvider indexed provider);
    event RegistrarSet(address indexed registrar, address indexed instance, bool canSetData);

    address multisig;
    Globals globals;
    MetadataRegistry registry;

    constructor() {
        multisig = _randomAddress();

        globals = new Globals(multisig);
        vm.prank(multisig);
        globals.setAddress(LibGlobals.GLOBAL_DAO_WALLET, multisig);
        registry = new MetadataRegistry(globals, new address[](0));
    }

    function test_setRegistrar_notAuthorized() public {
        address caller = _randomAddress();
        address instance = _randomAddress();

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(MetadataRegistry.NotAuthorized.selector, caller, instance)
        );
        registry.setRegistrar(_randomAddress(), instance, true);
    }

    function test_setRegistrar_asMultisig() public {
        address registrar = _randomAddress();
        address instance = _randomAddress();

        vm.prank(multisig);
        vm.expectEmit(true, true, true, true);
        emit RegistrarSet(registrar, instance, true);
        registry.setRegistrar(registrar, instance, true);

        assertTrue(registry.isRegistrar(registrar, instance));

        vm.prank(multisig);
        vm.expectEmit(true, true, true, true);
        emit RegistrarSet(registrar, instance, false);
        registry.setRegistrar(registrar, instance, false);

        assertFalse(registry.isRegistrar(registrar, instance));
    }

    function test_setRegistrar_asInstance() public {
        address registrar = _randomAddress();
        address instance = _randomAddress();

        vm.prank(instance);
        vm.expectEmit(true, true, true, true);
        emit RegistrarSet(registrar, instance, true);
        registry.setRegistrar(registrar, instance, true);

        assertTrue(registry.isRegistrar(registrar, instance));

        vm.prank(instance);
        vm.expectEmit(true, true, true, true);
        emit RegistrarSet(registrar, instance, false);
        registry.setRegistrar(registrar, instance, false);

        assertFalse(registry.isRegistrar(registrar, instance));
    }

    function test_setRegistrar_toUniversalRegistrar_notAuthorized() public {
        address caller = _randomAddress();

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(MetadataRegistry.NotAuthorized.selector, caller, address(1))
        );
        registry.setRegistrar(_randomAddress(), address(1), true);
    }

    function test_setRegistrar_toUniversalRegistrar_asMultisig() public {
        address registrar = _randomAddress();

        vm.prank(multisig);
        vm.expectEmit(true, true, true, true);
        emit RegistrarSet(registrar, address(1), true);
        registry.setRegistrar(registrar, address(1), true);

        address[] memory instances = new address[](3);
        instances[0] = _randomAddress();
        instances[1] = _randomAddress();
        instances[2] = _randomAddress();

        for (uint256 i = 0; i < instances.length; i++) {
            assertTrue(registry.isRegistrar(registrar, instances[i]));
        }
    }

    function test_setProvider_unauthorized() public {
        IMetadataProvider provider = IMetadataProvider(_randomAddress());
        address caller = _randomAddress();
        address instance = _randomAddress();

        // Attempt to set the provider
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(MetadataRegistry.NotAuthorized.selector, caller, instance)
        );
        registry.setProvider(instance, provider);
    }

    function test_setProvider_asInstance() public {
        IMetadataProvider provider = IMetadataProvider(_randomAddress());
        address instance = _randomAddress();

        // Set the provider
        vm.prank(instance);
        vm.expectEmit(true, true, true, true);
        emit ProviderSet(instance, provider);
        registry.setProvider(instance, provider);

        assertTrue(registry.getProvider(instance) == provider);
    }

    function test_setProvider_asRegistrar() public {
        IMetadataProvider provider = IMetadataProvider(_randomAddress());
        address registrar = _randomAddress();
        address instance = _randomAddress();

        // Set the registrar
        vm.prank(instance);
        registry.setRegistrar(registrar, instance, true);

        // Set the provider
        vm.prank(registrar);
        vm.expectEmit(true, true, true, true);
        emit ProviderSet(instance, provider);
        registry.setProvider(instance, provider);

        assertTrue(registry.getProvider(instance) == provider);
    }

    function test_setProvider_asUniversalRegistrar() public {
        IMetadataProvider provider = IMetadataProvider(_randomAddress());
        address registrar = _randomAddress();

        // Set the registrar
        vm.prank(multisig);
        registry.setRegistrar(registrar, address(1), true);

        // Set the provider
        address[] memory instances = new address[](3);
        instances[0] = _randomAddress();
        instances[1] = _randomAddress();
        instances[2] = _randomAddress();

        for (uint256 i; i < instances.length; ++i) {
            vm.prank(registrar);
            vm.expectEmit(true, true, true, true);
            emit ProviderSet(instances[i], provider);
            registry.setProvider(instances[i], provider);

            assertTrue(registry.getProvider(instances[i]) == provider);
        }
    }

    function test_getMetadata_works() public {
        MetadataProvider provider = new MetadataProvider(globals);
        address instance = _randomAddress();

        // Set the provider
        vm.prank(instance);
        registry.setProvider(instance, provider);

        // Set the metadata
        bytes memory metadata = abi.encodePacked(_randomBytes32());
        vm.prank(instance);
        provider.setMetadata(instance, metadata);

        assertEq(registry.getMetadata(instance, 0), metadata);
    }
}
