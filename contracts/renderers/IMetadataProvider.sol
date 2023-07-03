// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

interface IMetadataProvider {
    /// @notice Get the metadata for a Party instance.
    /// @param instance The address of the instance.
    /// @return metadata The encoded metadata.
    function getMetadata(address instance) external view returns (bytes memory metadata);
}
