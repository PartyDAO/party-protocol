// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { IGlobals } from "../globals/IGlobals.sol";
import { LibGlobals } from "../globals/LibGlobals.sol";
import { IMetadataProvider } from "./IMetadataProvider.sol";
import { Multicall } from "../utils/Multicall.sol";

/// @notice A registry of custom metadata providers for Party Cards.
contract MetadataRegistry is Multicall {
    event ProviderSet(address indexed instance, IMetadataProvider indexed provider);
    event RegistrarSet(address indexed registrar, address indexed instance, bool canSetData);

    error NotAuthorized(address caller, address instance);

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    /// @notice Get the metadata provider for a Party instance.
    mapping(address instance => IMetadataProvider provider) public getProvider;

    /// @notice Whether or not an address is a registar that can set the
    ///         provider and metadata for another instance. If registrar is set
    ///         true for `address(1)`, the address is a universal registar and
    ///         can set data for any instance.
    /// @dev Registrars' ability to set metadata for another instance must also be
    ///      supported by the metadata provider used by that instance, indicated by
    ///      `IMetadataProvider.supportsRegistrars()`.
    mapping(address registrar => mapping(address instance => bool canSetData)) private _isRegistrar;

    /// @param globals The address of the `Globals` contract.
    /// @param registrars The addresses of the initial universal registrars.
    constructor(IGlobals globals, address[] memory registrars) {
        _GLOBALS = globals;

        // Set the initial universal registrars.
        for (uint256 i = 0; i < registrars.length; i++) {
            _isRegistrar[registrars[i]][address(1)] = true;
        }
    }

    /// @notice Set the metadata provider for a Party instance.
    /// @param instance The address of the instance.
    /// @param provider The address of the metadata provider.
    function setProvider(address instance, IMetadataProvider provider) external {
        // Check if the caller is authorized to set the provider for the instance.
        if (!isRegistrar(msg.sender, instance)) revert NotAuthorized(msg.sender, instance);

        getProvider[instance] = provider;

        emit ProviderSet(instance, provider);
    }

    /// @notice Set whether or not an address can set metadata for a Party instance.
    /// @param registrar The address of the possible registrar.
    /// @param instance The address of the instance the registrar can set
    ///                 metadata for.
    /// @param canSetData Whether or not the address can set data for the instance.
    function setRegistrar(address registrar, address instance, bool canSetData) external {
        if (
            msg.sender != instance &&
            msg.sender != _GLOBALS.getAddress(LibGlobals.GLOBAL_DAO_WALLET)
        ) {
            revert NotAuthorized(msg.sender, instance);
        }

        _isRegistrar[registrar][instance] = canSetData;

        emit RegistrarSet(registrar, instance, canSetData);
    }

    /// @notice Get whether or not an address can set metadata for a Party instance.
    /// @param registrar The address of the possible registrar.
    /// @param instance The address of the instance the registrar can set
    ///                 metadata for.
    /// @return canSetData Whether or not the address can set data for the instance.
    function isRegistrar(address registrar, address instance) public view returns (bool) {
        return
            registrar == instance ||
            _isRegistrar[registrar][address(1)] ||
            _isRegistrar[registrar][instance];
    }

    /// @notice Get the metadata for a Party instance.
    /// @param instance The address of the instance.
    /// @param tokenId The ID of the token to get the metadata for.
    /// @return metadata The encoded metadata.
    function getMetadata(address instance, uint256 tokenId) external view returns (bytes memory) {
        IMetadataProvider provider = getProvider[instance];

        return
            address(provider) != address(0) ? provider.getMetadata(instance, tokenId) : bytes("");
    }
}
