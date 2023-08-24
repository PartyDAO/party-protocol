// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { Multicall } from "../utils/Multicall.sol";
import { MetadataRegistry } from "./MetadataRegistry.sol";
import { IMetadataProvider } from "./IMetadataProvider.sol";
import { IGlobals } from "../globals/IGlobals.sol";
import { LibGlobals } from "../globals/LibGlobals.sol";
import { SSTORE2 } from "solmate/utils/SSTORE2.sol";

/// @notice A contract that provides custom metadata for Party Cards and uses
///         SSTORE2 to store large metadata.
contract SSTORE2MetadataProvider is IMetadataProvider, Multicall {
    event MetadataSet(address indexed instance, Indexes indexes);

    error NotAuthorized(address caller, address instance);

    /// @notice The start and end index of metadata for a instance.
    struct Indexes {
        uint128 start;
        uint128 end;
    }

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    /// @inheritdoc IMetadataProvider
    bool public constant supportsRegistrars = true;

    /// @notice The next index to use for storing metadata.
    uint256 public nextIndex;

    /// @notice The metadata for each Party instance.
    mapping(uint256 index => address file) public files;

    /// @notice The start and end index of metadata for a instance.
    mapping(address instance => Indexes indexes) public indexes;

    // Set the `Globals` contract.
    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    /// @inheritdoc IMetadataProvider
    function getMetadata(address instance, uint256) external view returns (bytes memory data) {
        Indexes memory index = indexes[instance];
        for (uint256 i = index.start; i <= index.end; i++) {
            data = abi.encodePacked(data, SSTORE2.read(files[i]));
        }
    }

    /// @notice Set the metadata for a Party instance.
    /// @param instance The address of the instance.
    /// @param metadata The encoded metadata.
    function setMetadata(address instance, bytes calldata metadata) external {
        if (instance != msg.sender) {
            MetadataRegistry registry = MetadataRegistry(
                _GLOBALS.getAddress(LibGlobals.GLOBAL_METADATA_REGISTRY)
            );

            // Check if the caller is authorized to set metadata for the instance.
            if (!registry.isRegistrar(msg.sender, instance)) {
                revert NotAuthorized(msg.sender, instance);
            }
        }

        // Split the metadata into partitions of ~24KB max. The max bytecode we
        // want each partition to have after deployment is capped at 1 byte less
        // than the code size limit because SSTORE2 prefixes it with a 1 byte STOP
        // opcode to ensure it cannot be called as a normal contract.
        uint256 maxCodeSize = 24_575;
        uint256 metadataLength = metadata.length;
        uint256 partitions = metadataLength / maxCodeSize + 1;
        uint256 index = nextIndex;
        for (uint256 i; i < partitions; ++i) {
            uint256 start = i * maxCodeSize;
            uint256 end = start + maxCodeSize;
            if (end > metadataLength) end = metadataLength;

            files[index + i] = SSTORE2.write(metadata[start:end]);
        }

        Indexes memory instanceIndexes = indexes[instance] = Indexes({
            start: uint128(index),
            end: uint128(index + partitions - 1)
        });

        nextIndex += partitions;

        emit MetadataSet(instance, instanceIndexes);
    }
}
