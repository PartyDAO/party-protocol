// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { Multicall } from "../utils/Multicall.sol";
import { MetadataRegistry } from "./MetadataRegistry.sol";
import { IMetadataProvider } from "./IMetadataProvider.sol";
import { IGlobals } from "../globals/IGlobals.sol";
import { LibGlobals } from "../globals/LibGlobals.sol";

/// @notice A contract that provides custom metadata for Party Cards.
contract MetadataProvider is IMetadataProvider, Multicall {
    event MetadataSet(address indexed instance, bytes metadata);

    error NotAuthorized(address caller, address instance);

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals internal immutable _GLOBALS;

    /// @inheritdoc IMetadataProvider
    bool public constant supportsRegistrars = true;

    // The metadata for each Party instance.
    mapping(address instance => bytes metadata) internal _metadata;

    // Set the `Globals` contract.
    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    /// @inheritdoc IMetadataProvider
    function getMetadata(
        address instance,
        uint256
    ) external view virtual override returns (bytes memory) {
        return _metadata[instance];
    }

    /// @notice Set the metadata for a Party instance.
    /// @param instance The address of the instance.
    /// @param metadata The encoded metadata.
    function setMetadata(address instance, bytes memory metadata) external virtual {
        if (instance != msg.sender) {
            MetadataRegistry registry = MetadataRegistry(
                _GLOBALS.getAddress(LibGlobals.GLOBAL_METADATA_REGISTRY)
            );

            // Check if the caller is authorized to set metadata for the instance.
            if (!registry.isRegistrar(msg.sender, instance)) {
                revert NotAuthorized(msg.sender, instance);
            }
        }

        _metadata[instance] = metadata;

        emit MetadataSet(instance, metadata);
    }
}
