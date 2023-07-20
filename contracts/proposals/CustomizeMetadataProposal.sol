// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./IProposalExecutionEngine.sol";
import "../globals/LibGlobals.sol";
import "../renderers/MetadataRegistry.sol";
import "../renderers/MetadataProvider.sol";

// Implement a proposal for customizing the metadata for Party Cards.
abstract contract CustomizeMetadataProposal {
    struct CustomizeMetadataProposalData {
        // Provider of the metadata used for this Party.
        MetadataProvider provider;
        // Metadata to use for the Party.
        bytes metadata;
    }

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    // Set immutables.
    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    function _executeCustomizeMetadata(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal returns (bytes memory nextProgressData) {
        // Decode the proposal data.
        CustomizeMetadataProposalData memory data = abi.decode(
            params.proposalData,
            (CustomizeMetadataProposalData)
        );

        MetadataRegistry registry = MetadataRegistry(
            _GLOBALS.getAddress(LibGlobals.GLOBAL_METADATA_REGISTRY)
        );

        data.provider.setMetadata(msg.sender, data.metadata);
        registry.setProvider(msg.sender, data.provider);

        // Nothing left to do.
        return "";
    }
}
