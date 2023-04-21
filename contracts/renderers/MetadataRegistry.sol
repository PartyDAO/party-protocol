// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../globals/Globals.sol";
import "../crowdfund/Crowdfund.sol";
import "../party/Party.sol";

struct CollectionMetadata {
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
    event CustomPartyMetadataSet(Crowdfund indexed crowdfund, TokenMetadata metadata);
    event CustomPartyCollectionMetadataSet(
        Crowdfund indexed crowdfund,
        CollectionMetadata metadata
    );
    event AllowedHostSet(address indexed host, bool allowed);
    event AllowAnyHostEnabled();

    error HostNotFoundError(uint256 hostIndex, address[] hosts);
    error InvalidGovernanceOptionsError();
    error OnlyAllowedHostsError();
    error OnlyMultisigError();
    error InvalidCrowdfundError();
    error CannotSetMetadataForCrowdfundWithContributionsError();

    IGlobals private immutable _GLOBALS;

    constructor(IGlobals globals, address[] memory _allowedHosts) {
        _GLOBALS = globals;

        for (uint256 i; i < _allowedHosts.length; i++) {
            allowedHosts[_allowedHosts[i]] = true;
        }
    }

    /// @notice Whether any host is allowed to set custom token URIs or only allowed hosts.
    bool public allowAnyHost;
    /// @notice The address of the host that is allowed to set custom token URIs.
    mapping(address => bool) public allowedHosts;
    /// @notice The custom token URI metadata for the party created by a given crowdfund.
    mapping(Crowdfund => TokenMetadata) public customPartyMetadataByCrowdfund;
    /// @notice The custom contract URI metadata for the party created by a given crowdfund.
    mapping(Crowdfund => CollectionMetadata) public customPartyCollectionMetadataByCrowdfund;

    modifier onlyAllowedHostsIfSet() {
        if (!allowAnyHost && !allowedHosts[msg.sender]) revert OnlyAllowedHostsError();
        _;
    }

    modifier onlyMultisig() {
        if (msg.sender != _GLOBALS.multiSig()) revert OnlyMultisigError();
        _;
    }

    modifier onlyHost(
        Crowdfund crowdfund,
        Crowdfund.FixedGovernanceOpts memory governanceOpts,
        uint256 hostIndex
    ) {
        if (
            hostIndex < governanceOpts.hosts.length && msg.sender == governanceOpts.hosts[hostIndex]
        ) {
            // Validate governance opts if the host was found.
            if (crowdfund.governanceOptsHash() != _hashFixedGovernanceOpts(governanceOpts)) {
                revert InvalidGovernanceOptionsError();
            }
        } else {
            revert HostNotFoundError(hostIndex, governanceOpts.hosts);
        }

        _;
    }

    /// @notice Enable allowing any host to set custom metadata
    function enableAllowAnyHost() external onlyMultisig {
        allowAnyHost = true;

        emit AllowAnyHostEnabled();
    }

    /// @notice Set the status of a host as allowed to set custom token URIs or not
    /// @param host The host to set the status of
    /// @param allowed Whether the host is allowed or not
    function setAllowedHost(address host, bool allowed) external onlyMultisig {
        allowedHosts[host] = allowed;

        emit AllowedHostSet(host, allowed);
    }

    /// @notice Set the custom token URI for a party created by a given crowdfund.
    /// @param crowdfund The crowdfund that created the party.
    /// @param metadata The metadata for the custom token URI to set for the party's token.
    function setCustomMetadata(
        Crowdfund crowdfund,
        Crowdfund.FixedGovernanceOpts memory governanceOpts,
        uint256 hostIndex,
        TokenMetadata memory metadata
    ) external onlyHost(crowdfund, governanceOpts, hostIndex) onlyAllowedHostsIfSet {
        if (address(crowdfund) == address(0)) {
            revert InvalidCrowdfundError();
        }

        // Only allow setting the metadata before anyone has contributed to the
        // crowdfund.
        if (crowdfund.totalContributions() != 0) {
            revert CannotSetMetadataForCrowdfundWithContributionsError();
        }

        customPartyMetadataByCrowdfund[crowdfund] = metadata;

        emit CustomPartyMetadataSet(crowdfund, metadata);
    }

    /// @notice Set the custom contract URI for a party created by a given crowdfund.
    /// @param crowdfund The crowdfund that created the party.
    /// @param metadata The metadata for the custom contract URI to set for the party's contract.
    function setCustomCollectionMetadata(
        Crowdfund crowdfund,
        Crowdfund.FixedGovernanceOpts memory governanceOpts,
        uint256 hostIndex,
        CollectionMetadata memory metadata
    ) external onlyHost(crowdfund, governanceOpts, hostIndex) onlyAllowedHostsIfSet {
        if (address(crowdfund) == address(0)) {
            revert InvalidCrowdfundError();
        }

        // Only allow setting the metadata before anyone has contributed to the
        // crowdfund.
        if (crowdfund.totalContributions() != 0) {
            revert CannotSetMetadataForCrowdfundWithContributionsError();
        }

        customPartyCollectionMetadataByCrowdfund[crowdfund] = metadata;

        emit CustomPartyCollectionMetadataSet(crowdfund, metadata);
    }
}
