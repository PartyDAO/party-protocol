// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { Test } from "forge-std/Test.sol";
import { Globals } from "../../contracts/globals/Globals.sol";
import { MetadataProvider } from "../../contracts/renderers/MetadataProvider.sol";
import { GlobalsAdmin } from "../TestUsers.sol";
import { MetadataRegistry } from "../../contracts/renderers/MetadataRegistry.sol";
import { PartyNFTRenderer } from "../../contracts/renderers/PartyNFTRenderer.sol";
import "../TestUtils.sol";

abstract contract BaseMetadataProviderTest is TestUtils {
    Globals globals;
    GlobalsAdmin globalsAdmin;
    MetadataProvider metadataProvider;
    string public name = "Party Name";

    function setUp() public virtual {
        globalsAdmin = new GlobalsAdmin();
        globals = globalsAdmin.globals();
        address[] memory registrars = new address[](1);
        registrars[0] = address(this);
        globalsAdmin.setMetadataRegistry(address(new MetadataRegistry(globals, registrars)));
    }

    function test_setMetadata_authorizedRegistrar() public {
        PartyNFTRenderer.Metadata memory metadata = PartyNFTRenderer.Metadata({
            name: "", // This will be set to the Party's name.
            description: "This is a description. Let's give it some more text to ensure it is a dynamic type. Even some more to ensure it takes up more than two slots. Good, this should be enough data",
            externalURL: "https://example.com",
            image: "ipfs://image",
            banner: "ipfs://banner",
            animationURL: "https://example.com/animation",
            collectionName: "", // This will be set to the Party's name.
            collectionDescription: "", // This will be set to the Party's description.
            collectionExternalURL: "https://example.com/collection",
            royaltyReceiver: _randomAddress(),
            royaltyAmount: _randomUint256(),
            renderingMethod: PartyNFTRenderer.RenderingMethod.FixedCrowdfund
        });
        metadataProvider.setMetadata(address(0x123), abi.encode(metadata));
    }

    function test_setMetadata_unauthorized() public {
        PartyNFTRenderer.Metadata memory metadata = PartyNFTRenderer.Metadata({
            name: "", // This will be set to the Party's name.
            description: "This is a description. Let's give it some more text to ensure it is a dynamic type. Even some more to ensure it takes up more than two slots. Good, this should be enough data",
            externalURL: "https://example.com",
            image: "ipfs://image",
            banner: "ipfs://banner",
            animationURL: "https://example.com/animation",
            collectionName: "", // This will be set to the Party's name.
            collectionDescription: "", // This will be set to the Party's description.
            collectionExternalURL: "https://example.com/collection",
            royaltyReceiver: _randomAddress(),
            royaltyAmount: _randomUint256(),
            renderingMethod: PartyNFTRenderer.RenderingMethod.ENUM_OFFSET
        });
        vm.prank(address(0x1234));
        vm.expectRevert(
            abi.encodeWithSelector(
                MetadataProvider.NotAuthorized.selector,
                address(0x1234),
                address(0x123)
            )
        );
        metadataProvider.setMetadata(address(0x123), abi.encode(metadata));
    }
}
