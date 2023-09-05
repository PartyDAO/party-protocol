// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { BaseMetadataProviderTest } from "./BaseMetadataProviderTest.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/renderers/MetadataProvider.sol";
import "../../contracts/renderers/SSTORE2MetadataProvider.sol";

contract SSTORE2MetadataProviderTest is BaseMetadataProviderTest {
    function setUp() public override {
        super.setUp();
        metadataProvider = new SSTORE2MetadataProvider(globals);
    }

    function test_setMetadata() public {
        PartyNFTRenderer.Metadata memory metadata = PartyNFTRenderer.Metadata({
            name: "", // This will be set to the Party's name.
            description: "This is a description.",
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
        metadataProvider.setMetadata(address(this), abi.encode(metadata));

        PartyNFTRenderer.Metadata memory expectedMetadata = metadata;
        expectedMetadata.name = expectedMetadata.collectionName = name;
        expectedMetadata.collectionDescription = metadata.description;
        assertEq(metadataProvider.getMetadata(address(this), 0), abi.encode(expectedMetadata));
    }
}
