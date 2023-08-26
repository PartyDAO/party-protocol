// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/party/PartyFactory.sol";
import "../../contracts/globals/Globals.sol";
import "../TestUtils.sol";
import "../../contracts/proposals/ProposalExecutionEngine.sol";
import { MockZoraReserveAuctionCoreEth } from "../proposals/MockZoraReserveAuctionCoreEth.sol";
import "../../contracts/renderers/MetadataProvider.sol";
import "../../contracts/renderers/MetadataRegistry.sol";

contract PartyFactoryTest is Test, TestUtils {
    Globals globals = new Globals(address(this));
    Party partyImpl = new Party(globals);
    PartyFactory factory = new PartyFactory(globals);
    MetadataRegistry registry = new MetadataRegistry(globals, _toAddressArray(address(factory)));
    MetadataProvider provider = new MetadataProvider(globals);
    ProposalExecutionEngine eng;
    Party.PartyOptions defaultPartyOptions;

    constructor() {
        defaultPartyOptions.name = "PARTY";
        defaultPartyOptions.symbol = "PR-T";
        defaultPartyOptions.governance.hosts.push(_randomAddress());
        defaultPartyOptions.governance.hosts.push(_randomAddress());
        defaultPartyOptions.governance.voteDuration = 1 days;
        defaultPartyOptions.governance.executionDelay = 8 hours;
        defaultPartyOptions.governance.passThresholdBps = 0.51e4;
        defaultPartyOptions.governance.totalVotingPower = 100e18;

        eng = new ProposalExecutionEngine(
            globals,
            new MockZoraReserveAuctionCoreEth(),
            IFractionalV1VaultFactory(_randomAddress())
        );

        globals.setAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL, address(eng));
        globals.setAddress(LibGlobals.GLOBAL_METADATA_REGISTRY, address(registry));
    }

    function _createPreciouses(
        uint256 count
    ) private view returns (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) {
        preciousTokens = new IERC721[](count);
        preciousTokenIds = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            preciousTokens[i] = IERC721(_randomAddress());
            preciousTokenIds[i] = _randomUint256();
        }
    }

    function _hashPreciousList(
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) internal pure returns (bytes32 h) {
        assembly {
            mstore(0x00, keccak256(add(preciousTokens, 0x20), mul(mload(preciousTokens), 0x20)))
            mstore(0x20, keccak256(add(preciousTokenIds, 0x20), mul(mload(preciousTokenIds), 0x20)))
            h := keccak256(0x00, 0x40)
        }
    }

    function testCreateParty(
        string memory randomStr,
        uint96 randomUint96,
        uint40 randomUint40,
        uint16 randomBps,
        bool randomBool
    ) external {
        vm.assume(randomBps <= 1e4);

        address authority = _randomAddress();
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) = _createPreciouses(3);
        Party.PartyOptions memory opts = Party.PartyOptions({
            governance: PartyGovernance.GovernanceOpts({
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: randomUint40,
                executionDelay: randomUint40,
                passThresholdBps: randomBps,
                totalVotingPower: randomUint96,
                feeBps: randomBps,
                feeRecipient: payable(_randomAddress())
            }),
            proposalEngine: ProposalStorage.ProposalEngineOpts({
                enableAddAuthorityProposal: randomBool,
                allowArbCallsToSpendPartyEth: randomBool,
                allowOperators: randomBool,
                distributionsRequireVote: randomBool
            }),
            name: randomStr,
            symbol: randomStr,
            customizationPresetId: 0
        });
        Party party = factory.createParty(
            partyImpl,
            _toAddressArray(authority),
            opts,
            preciousTokens,
            preciousTokenIds,
            randomUint40
        );
        assertEq(party.VERSION_ID(), 1);
        assertEq(party.name(), opts.name);
        assertEq(party.symbol(), opts.symbol);
        assertTrue(party.isAuthority(authority));
        assertEq(party.rageQuitTimestamp(), randomUint40);
        PartyGovernance.GovernanceValues memory values = party.getGovernanceValues();
        assertEq(values.voteDuration, opts.governance.voteDuration);
        assertEq(values.executionDelay, opts.governance.executionDelay);
        assertEq(values.passThresholdBps, opts.governance.passThresholdBps);
        assertEq(values.totalVotingPower, opts.governance.totalVotingPower);
        assertEq(party.feeBps(), opts.governance.feeBps);
        assertEq(party.feeRecipient(), opts.governance.feeRecipient);
        assertEq(address(party.getProposalExecutionEngine()), address(eng));
        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts = party
            .getProposalEngineOpts();
        assertEq(proposalEngineOpts.allowArbCallsToSpendPartyEth, randomBool);
        assertEq(proposalEngineOpts.allowOperators, randomBool);
        assertEq(proposalEngineOpts.distributionsRequireVote, randomBool);
        assertEq(party.preciousListHash(), _hashPreciousList(preciousTokens, preciousTokenIds));
    }

    function testCreatePartyWithMetadata(
        string memory randomStr,
        uint96 randomUint96,
        uint40 randomUint40,
        uint16 randomBps,
        bool randomBool,
        bytes memory metadata
    ) external {
        vm.assume(randomBps <= 1e4);

        address authority = _randomAddress();
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) = _createPreciouses(3);
        Party.PartyOptions memory opts = Party.PartyOptions({
            governance: PartyGovernance.GovernanceOpts({
                hosts: _toAddressArray(_randomAddress()),
                voteDuration: randomUint40,
                executionDelay: randomUint40,
                passThresholdBps: randomBps,
                totalVotingPower: randomUint96,
                feeBps: randomBps,
                feeRecipient: payable(_randomAddress())
            }),
            proposalEngine: ProposalStorage.ProposalEngineOpts({
                enableAddAuthorityProposal: randomBool,
                allowArbCallsToSpendPartyEth: randomBool,
                allowOperators: randomBool,
                distributionsRequireVote: randomBool
            }),
            name: randomStr,
            symbol: randomStr,
            customizationPresetId: 0
        });
        Party party = factory.createPartyWithMetadata(
            partyImpl,
            _toAddressArray(authority),
            opts,
            preciousTokens,
            preciousTokenIds,
            randomUint40,
            provider,
            metadata
        );

        assertEq(party.VERSION_ID(), 1);
        assertEq(party.name(), opts.name);
        assertEq(party.symbol(), opts.symbol);
        assertTrue(party.isAuthority(authority));
        assertEq(party.rageQuitTimestamp(), randomUint40);
        PartyGovernance.GovernanceValues memory values = party.getGovernanceValues();
        assertEq(values.voteDuration, opts.governance.voteDuration);
        assertEq(values.executionDelay, opts.governance.executionDelay);
        assertEq(values.passThresholdBps, opts.governance.passThresholdBps);
        assertEq(values.totalVotingPower, opts.governance.totalVotingPower);
        assertEq(party.feeBps(), opts.governance.feeBps);
        assertEq(party.feeRecipient(), opts.governance.feeRecipient);
        assertEq(address(party.getProposalExecutionEngine()), address(eng));
        ProposalStorage.ProposalEngineOpts memory proposalEngineOpts = party
            .getProposalEngineOpts();
        assertEq(proposalEngineOpts.allowArbCallsToSpendPartyEth, randomBool);
        assertEq(proposalEngineOpts.allowOperators, randomBool);
        assertEq(proposalEngineOpts.distributionsRequireVote, randomBool);
        assertEq(party.preciousListHash(), _hashPreciousList(preciousTokens, preciousTokenIds));
        assertEq(address(registry.getProvider(address(party))), address(provider));
        assertEq(provider.getMetadata(address(party), 0), metadata);
    }

    function testCreatePartyWithInvalidBps(uint16 passThresholdBps, uint16 feeBps) external {
        // At least one of the BPs must be invalid for this test to work.
        vm.assume(passThresholdBps > 1e4 || feeBps > 1e4);

        address authority = _randomAddress();
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) = _createPreciouses(3);

        Party.PartyOptions memory opts = defaultPartyOptions;
        opts.governance.feeBps = feeBps;
        opts.governance.passThresholdBps = passThresholdBps;

        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.InvalidBpsError.selector,
                feeBps > 1e4 ? feeBps : passThresholdBps
            )
        );
        factory.createParty(
            partyImpl,
            _toAddressArray(authority),
            opts,
            preciousTokens,
            preciousTokenIds,
            0
        );
    }
}
