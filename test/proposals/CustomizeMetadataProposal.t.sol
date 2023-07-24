// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "contracts/globals/Globals.sol";
import "contracts/renderers/MetadataRegistry.sol";
import "contracts/renderers/MetadataProvider.sol";

import "forge-std/Test.sol";
import "../../contracts/proposals/CustomizeMetadataProposal.sol";
import "../TestUtils.sol";

contract TestableCustomizeMetadataProposal is CustomizeMetadataProposal {
    constructor(IGlobals globals) CustomizeMetadataProposal(globals) {}

    function execute(
        IProposalExecutionEngine.ExecuteProposalParams calldata params
    ) external returns (bytes memory nextProgressData) {
        nextProgressData = _executeCustomizeMetadata(params);
    }
}

contract CustomizeMetadataProposalTest is Test, TestUtils {
    Globals globals;
    TestableCustomizeMetadataProposal proposal;
    MetadataRegistry registry;
    MetadataProvider provider;

    constructor() {
        globals = new Globals(address(this));
        proposal = new TestableCustomizeMetadataProposal(globals);
        registry = new MetadataRegistry(globals, _toAddressArray(address(this)));
        provider = new MetadataProvider(globals);
        globals.setAddress(LibGlobals.GLOBAL_METADATA_REGISTRY, address(registry));
    }

    function test_executeCustomizeMetadata_works() public {
        CustomizeMetadataProposal.CustomizeMetadataProposalData
            memory data = CustomizeMetadataProposal.CustomizeMetadataProposalData({
                provider: provider,
                metadata: "CUSTOM_METADATA"
            });

        // Execute the proposal.
        bytes memory nextProgressData = proposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: "",
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            })
        );

        assertEq(nextProgressData.length, 0);
        assertEq(provider.getMetadata(address(proposal), 0), "CUSTOM_METADATA");
        assertEq(address(registry.getProvider(address(proposal))), address(provider));
    }

    function test_executeCustomizeMetadata_noMetadata() public {
        CustomizeMetadataProposal.CustomizeMetadataProposalData
            memory data = CustomizeMetadataProposal.CustomizeMetadataProposalData({
                provider: provider,
                metadata: ""
            });

        // Execute the proposal.
        bytes memory nextProgressData = proposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: "",
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            })
        );

        assertEq(nextProgressData.length, 0);
        assertEq(provider.getMetadata(address(proposal), 0), "");
        assertEq(address(registry.getProvider(address(proposal))), address(provider));
    }
}
