// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../globals/Globals.sol";
import "../crowdfund/Crowdfund.sol";
import "../party/Party.sol";

struct ContractMetadata {
    string name;
    string description;
    string image;
    string banner;
}

struct TokenMetadata {
    string name;
    string description;
    string image;
}

contract MetadataRegistry {
    error MetadataAlreadySetError();
    error OnlyAllowedHostsError();
    error OnlyMultisigError();
    error InvalidCrowdfundError();

    Globals private immutable _GLOBALS;

    /// @notice The address of the host that is allowed to set custom token URIs
    mapping(address => bool) public allowedHosts;
    /// @notice The custom token URI metadata for the party created by a given crowdfund
    mapping(Crowdfund => TokenMetadata) public customPartyTokenURIByCrowdfund;
    /// @notice The custom contract URI metadata for the party created by a given crowdfund
    mapping(Crowdfund => ContractMetadata) public customPartyContractURIByCrowdfund;

    constructor(Globals global, address[] memory _allowedHosts) {
        _GLOBALS = global;

        for (uint256 i; i < _allowedHosts.length; i++) {
            allowedHosts[_allowedHosts[i]] = true;
        }
    }

    modifier onlyAllowedHosts() {
        if (!allowedHosts[msg.sender]) revert OnlyAllowedHostsError();
        _;
    }

    modifier onlyMultisig() {
        if (msg.sender != _GLOBALS.multiSig()) revert OnlyMultisigError();
        _;
    }

    /// @notice Set the status of a host as allowed to set custom token URIs or not
    /// @param host The host to set the status of
    /// @param allowed Whether the host is allowed or not
    function setAllowedHosts(address host, bool allowed) external onlyMultisig {
        allowedHosts[host] = allowed;
    }

    /// @notice Set the custom token URI for a party created by a given crowdfund
    /// @param crowdfund The crowdfund that created the party
    /// @param metadata The metadata for the custom token URI to set for the party's token
    function setCustomTokenURI(
        Crowdfund crowdfund,
        TokenMetadata memory metadata
    ) external onlyAllowedHosts {
        if (address(crowdfund) == address(0)) {
            revert InvalidCrowdfundError();
        }

        // Prevent setting the metadata if it has already been set
        TokenMetadata memory _metadata = customPartyTokenURIByCrowdfund[crowdfund];
        if (
            bytes(_metadata.name).length > 0 ||
            bytes(_metadata.description).length > 0 ||
            bytes(_metadata.image).length > 0
        ) {
            revert MetadataAlreadySetError();
        }

        customPartyTokenURIByCrowdfund[crowdfund] = metadata;
    }

    /// @notice Set the custom contract URI for a party created by a given crowdfund
    /// @param crowdfund The crowdfund that created the party
    /// @param metadata The metadata for the custom contract URI to set for the party's contract
    function setCustomContractURI(
        Crowdfund crowdfund,
        ContractMetadata memory metadata
    ) external onlyAllowedHosts {
        if (address(crowdfund) == address(0)) {
            revert InvalidCrowdfundError();
        }

        // Prevent setting the metadata if it has already been set
        ContractMetadata memory _metadata = customPartyContractURIByCrowdfund[crowdfund];
        if (
            bytes(_metadata.name).length > 0 ||
            bytes(_metadata.description).length > 0 ||
            bytes(_metadata.image).length > 0 ||
            bytes(_metadata.banner).length > 0
        ) {
            revert MetadataAlreadySetError();
        }

        customPartyContractURIByCrowdfund[crowdfund] = metadata;
    }
}
