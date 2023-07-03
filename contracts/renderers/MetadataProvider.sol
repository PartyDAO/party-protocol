// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./IMetadataProvider.sol";

/// @notice A contract that provides custom metadata for Party Cards.
contract MetadataProvider is IMetadataProvider {
    /// @inheritdoc IMetadataProvider
    mapping(address instance => bytes metadata) public getMetadata;

    /// @notice Set the metadata for a Party instance.
    /// @param metadata The encoded metadata.
    function setMetadata(bytes memory metadata) external {
        getMetadata[msg.sender] = metadata;
    }
}
