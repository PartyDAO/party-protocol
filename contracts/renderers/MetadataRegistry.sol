// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../globals/IGlobals.sol";
import "./IMetadataProvider.sol";

/// @notice A registry of custom metadata providers for Party Cards.
contract MetadataRegistry {
    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    /// @notice Get the metadata provider for a Party instance.
    mapping(address instance => IMetadataProvider provider) public getProvider;

    // Set the `Globals` contract.
    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    /// @notice Set the metadata provider for a Party instance.
    /// @param provider The address of the metadata provider.
    function setProvider(IMetadataProvider provider) public {
        getProvider[msg.sender] = provider;
    }

    /// @notice Get the metadata for a Party instance.
    /// @param instance The address of the instance.
    /// @return metadata The encoded metadata.
    function getMetadata(address instance) external view returns (bytes memory) {
        IMetadataProvider provider = getProvider[instance];
        return address(provider) != address(0) ? provider.getMetadata(instance) : bytes("");
    }
}
