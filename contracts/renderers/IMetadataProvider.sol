// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

interface IMetadataProvider {
    /// @notice Whether or not the metadata provider supports registrars that can
    ///         set metadata for other instances.
    /// @dev See `MetadataRegistry` for more information on the registrar role.
    function supportsRegistrars() external view returns (bool);

    /// @notice Get the metadata for a Party instance.
    /// @param instance The address of the instance.
    /// @param tokenId The ID of the token to get the metadata for.
    /// @return metadata The encoded metadata.
    function getMetadata(
        address instance,
        uint256 tokenId
    ) external view returns (bytes memory metadata);
}
