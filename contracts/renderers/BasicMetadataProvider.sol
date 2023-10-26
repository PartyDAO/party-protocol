// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { Party } from "../party/Party.sol";
import { MetadataRegistry } from "./MetadataRegistry.sol";
import { MetadataProvider } from "./MetadataProvider.sol";
import { IGlobals } from "../globals/IGlobals.sol";
import { LibGlobals } from "../globals/LibGlobals.sol";
import { PartyNFTRenderer } from "./PartyNFTRenderer.sol";

/// @notice A contract that provides custom metadata for Party Cards.
contract BasicMetadataProvider is MetadataProvider {
    error MetadataTooLarge();

    constructor(IGlobals globals) MetadataProvider(globals) {}

    /// @inheritdoc MetadataProvider
    function getMetadata(address instance, uint256) external view override returns (bytes memory) {
        Metadata memory metadata;

        metadata.name = metadata.collectionName = Party(payable(instance)).name();
        metadata.description = metadata.collectionDescription = retrieveDynamicMetadataInfo(
            instance,
            MetadataFields.DESCRIPTION
        );
        metadata.externalURL = retrieveDynamicMetadataInfo(instance, MetadataFields.EXTERNAL_URL);
        metadata.image = retrieveDynamicMetadataInfo(instance, MetadataFields.IMAGE);
        metadata.banner = retrieveDynamicMetadataInfo(instance, MetadataFields.BANNER);
        metadata.animationURL = retrieveDynamicMetadataInfo(instance, MetadataFields.ANIMATION_URL);
        metadata.collectionExternalURL = retrieveDynamicMetadataInfo(
            instance,
            MetadataFields.COLLECTION_EXTERNAL_URL
        );
        metadata.royaltyReceiver = address(
            uint160(uint256(retrieveValueMetadataInfo(instance, MetadataFields.ROYALTY_RECEIVER)))
        );
        metadata.royaltyAmount = uint256(
            retrieveValueMetadataInfo(instance, MetadataFields.ROYALTY_AMOUNT)
        );
        metadata.renderingMethod = PartyNFTRenderer.RenderingMethod(
            uint256(retrieveValueMetadataInfo(instance, MetadataFields.RENDERING_METHOD))
        );

        return abi.encode(metadata);
    }

    struct Metadata {
        string name;
        bytes description;
        bytes externalURL;
        bytes image;
        bytes banner;
        bytes animationURL;
        string collectionName;
        bytes collectionDescription;
        bytes collectionExternalURL;
        address royaltyReceiver;
        uint256 royaltyAmount;
        PartyNFTRenderer.RenderingMethod renderingMethod;
    }

    /// @notice Set the metadata for a Party instance.
    /// @param instance The address of the instance.
    /// @param metadata The encoded metadata.
    function setMetadata(address instance, bytes calldata metadata) external override {
        if (instance != msg.sender) {
            MetadataRegistry registry = MetadataRegistry(
                _GLOBALS.getAddress(LibGlobals.GLOBAL_METADATA_REGISTRY)
            );

            // Check if the caller is authorized to set metadata for the instance.
            if (!registry.isRegistrar(msg.sender, instance)) {
                revert NotAuthorized(msg.sender, instance);
            }
        }

        Metadata memory decodedMetadata = abi.decode(metadata, (Metadata));

        if (decodedMetadata.description.length != 0) {
            storeMetadataInfo(
                instance,
                MetadataFields.DESCRIPTION,
                decodedMetadata.description,
                false
            );
        }

        if (decodedMetadata.externalURL.length != 0) {
            storeMetadataInfo(
                instance,
                MetadataFields.EXTERNAL_URL,
                decodedMetadata.externalURL,
                false
            );
        }

        if (decodedMetadata.image.length != 0) {
            storeMetadataInfo(instance, MetadataFields.IMAGE, decodedMetadata.image, false);
        }

        if (decodedMetadata.banner.length != 0) {
            storeMetadataInfo(instance, MetadataFields.BANNER, decodedMetadata.banner, false);
        }

        if (decodedMetadata.animationURL.length != 0) {
            storeMetadataInfo(
                instance,
                MetadataFields.ANIMATION_URL,
                decodedMetadata.animationURL,
                false
            );
        }

        if (decodedMetadata.collectionExternalURL.length != 0) {
            storeMetadataInfo(
                instance,
                MetadataFields.COLLECTION_EXTERNAL_URL,
                decodedMetadata.collectionExternalURL,
                false
            );
        }

        if (decodedMetadata.royaltyReceiver != address(0)) {
            storeMetadataInfo(
                instance,
                MetadataFields.ROYALTY_RECEIVER,
                abi.encode(decodedMetadata.royaltyReceiver),
                true
            );
        }

        if (decodedMetadata.royaltyAmount != 0) {
            storeMetadataInfo(
                instance,
                MetadataFields.ROYALTY_AMOUNT,
                abi.encode(decodedMetadata.royaltyAmount),
                true
            );
        }

        if (decodedMetadata.renderingMethod != PartyNFTRenderer.RenderingMethod.ENUM_OFFSET) {
            storeMetadataInfo(
                instance,
                MetadataFields.RENDERING_METHOD,
                abi.encode(decodedMetadata.renderingMethod),
                true
            );
        }

        emit MetadataSet(instance, metadata);
    }

    /// @notice The indexes of the metadata fields in storage (if dynamic contains a start slot)
    enum MetadataFields {
        DESCRIPTION,
        EXTERNAL_URL,
        IMAGE,
        BANNER,
        ANIMATION_URL,
        COLLECTION_EXTERNAL_URL,
        ROYALTY_RECEIVER,
        ROYALTY_AMOUNT,
        RENDERING_METHOD
    }

    /// @notice Stores a metadata field to storage
    /// @param instance The instance to store the metadata for
    /// @param field The field to store
    /// @param data The data to store
    /// @param isValue Whether the data is a value type or a dynamic type
    function storeMetadataInfo(
        address instance,
        MetadataFields field,
        bytes memory data,
        bool isValue
    ) private {
        uint256 metadataSlot;
        assembly {
            metadataSlot := _metadata.slot
        }
        uint256 slot = uint256(keccak256(abi.encode(instance, metadataSlot))) + uint8(field);

        uint256 value;
        assembly {
            value := mload(add(data, 0x20))
        }

        if (!isValue) {
            // Check if we can force the data into a single slot
            uint256 dataLength = data.length;
            // We use the first bit as a signal that the data is an slot number
            if (dataLength > 32 || (dataLength == 32 && value >> 255 == 1)) {
                if (dataLength > type(uint16).max) {
                    revert MetadataTooLarge();
                }
                // Store the slot to the start of this data (first bit 1 indicates its a slot)
                uint256 dynamicSlot = (uint256(1) << 255) |
                    uint256(keccak256(abi.encode(instance, metadataSlot, field)));
                assembly {
                    // Store the dynamic data start slot in the value slot
                    sstore(slot, dynamicSlot)
                }

                // Store first slot with first 16 bits as size
                uint16 length = uint16(data.length);
                assembly {
                    sstore(dynamicSlot, or(shl(240, length), shr(16, mload(add(data, 0x20)))))
                }

                for (uint256 i = 30; i < data.length; i += 32) {
                    uint256 mask = type(uint256).max;
                    if (data.length < i + 32) {
                        // Don't store the whole slot bc less than a slot worth of data
                        mask = mask << (256 - (data.length - i) * 8);
                    }

                    uint256 slotIncrement = i + 2;
                    bytes32 toStore;

                    assembly {
                        toStore := mload(add(i, add(0x20, data)))
                        toStore := and(toStore, mask)
                        sstore(add(dynamicSlot, slotIncrement), toStore)
                    }
                }
                return;
            }

            // Shift data to right side of slot
            value = value >> (256 - dataLength * 8);
        }

        // treating as value type
        assembly {
            sstore(slot, value)
        }
    }

    /// @notice Retrieves a value metadata field from storage
    function retrieveValueMetadataInfo(
        address instance,
        MetadataFields field
    ) private view returns (bytes32 res) {
        uint256 metadataSlotNumber;
        assembly {
            metadataSlotNumber := _metadata.slot
        }
        uint256 slot = uint256(keccak256(abi.encode(instance, metadataSlotNumber))) + uint8(field);
        assembly {
            res := sload(slot)
        }
    }

    /// @notice Retrieves a dynamic metadata field from storage
    function retrieveDynamicMetadataInfo(
        address instance,
        MetadataFields field
    ) private view returns (bytes memory) {
        uint256 metadataSlotNumber;
        assembly {
            metadataSlotNumber := _metadata.slot
        }
        uint256 slot = uint256(keccak256(abi.encode(instance, metadataSlotNumber))) + uint8(field);
        bytes32 slotData;
        assembly {
            slotData := sload(slot)
        }
        if (slotData >> 255 == 0) {
            // Remove extra zeros from the data
            bytes memory returnData;
            assembly {
                let dataSize := 0
                for {
                    let i := 0
                } lt(i, 32) {
                    i := add(i, 1)
                } {
                    if iszero(shr(mul(i, 8), slotData)) {
                        dataSize := i
                        break
                    }
                }
                let freeMem := mload(0x40)
                mstore(freeMem, dataSize)
                mstore(add(freeMem, 0x20), shl(sub(256, mul(dataSize, 8)), slotData))
                mstore(0x40, add(freeMem, 0x40))
                returnData := freeMem
            }
            return returnData;
        }

        // Retrieve dymanic data from dynamic slot
        bytes32 firstSlotDynamic;

        bytes memory res;
        assembly {
            res := mload(0x40)
            firstSlotDynamic := sload(slotData)
            mstore(add(res, 30), firstSlotDynamic)
            mstore(0x40, add(res, add(shr(240, firstSlotDynamic), 0x20)))
        }

        for (uint256 i = 32; i < res.length; i += 32) {
            uint256 slotIncrement = i + 30;
            bytes32 data;
            assembly {
                data := sload(add(slotData, i))
                mstore(add(res, slotIncrement), data)
            }
        }

        return res;
    }
}
