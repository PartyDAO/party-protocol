// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { BondingCurveAuthority } from "contracts/authorities/BondingCurveAuthority.sol";
import { PartyFactory } from "contracts/party/PartyFactory.sol";
import { Party } from "contracts/party/Party.sol";
import { PartyGovernance } from "contracts/party/PartyGovernance.sol";
import { MetadataProvider } from "contracts/renderers/MetadataProvider.sol";
import { PartyNFTRenderer } from "contracts/renderers/PartyNFTRenderer.sol";
import { ProposalStorage } from "contracts/proposals/ProposalStorage.sol";
import { ERC721Receiver } from "contracts/tokens/ERC721Receiver.sol";

contract EZPartyBuilder is ERC721Receiver {
    event EZPartyCreated(Party indexed party, address host, address[] initialMembers);

    error PartyAlreadyCreated();

    address payable immutable TREASURY;
    BondingCurveAuthority public immutable BONDING_CURVE_AUTHORITY;
    PartyFactory public immutable PARTY_FACTORY;
    Party public immutable PARTY_IMPLEMENTATION;
    MetadataProvider public immutable METADATA_PROVIDER;

    mapping(address => bool) public hasAlreadyCreatedParty;

    constructor(
        address payable treasury,
        BondingCurveAuthority bondingCurveAuthority,
        PartyFactory partyFactory,
        Party partyImplementation,
        MetadataProvider metadataProvider
    ) {
        TREASURY = treasury;
        BONDING_CURVE_AUTHORITY = bondingCurveAuthority;
        PARTY_FACTORY = partyFactory;
        PARTY_IMPLEMENTATION = partyImplementation;
        METADATA_PROVIDER = metadataProvider;
    }

    function createPartyAndDistributeMemberships(
        address host,
        address[] calldata initialMembers,
        string memory partyName,
        string memory partySymbol,
        string memory imageUri
    ) external payable returns (Party party) {
        if (hasAlreadyCreatedParty[host]) revert PartyAlreadyCreated();

        hasAlreadyCreatedParty[host] = true;

        PartyNFTRenderer.Metadata memory metadata;
        metadata.image = imageUri;

        address[] memory hosts = new address[](1);
        hosts[0] = host;

        // Create Party and mint cards to distribute to all members.
        party = BONDING_CURVE_AUTHORITY.createPartyWithMetadata{ value: msg.value }(
            BondingCurveAuthority.BondingCurvePartyOptions({
                partyFactory: PARTY_FACTORY,
                partyImpl: PARTY_IMPLEMENTATION,
                opts: Party.PartyOptions({
                    governance: PartyGovernance.GovernanceOpts({
                        hosts: hosts,
                        voteDuration: 7 days,
                        executionDelay: 7 days,
                        passThresholdBps: 3000, // 30%
                        totalVotingPower: 0,
                        feeBps: TREASURY == address(0) ? 0 : 250, // 2.5%
                        feeRecipient: TREASURY
                    }),
                    proposalEngine: ProposalStorage.ProposalEngineOpts({
                        enableAddAuthorityProposal: false,
                        allowArbCallsToSpendPartyEth: true,
                        allowOperators: true,
                        distributionsConfig: ProposalStorage.DistributionsConfig.NotAllowed
                    }),
                    name: partyName,
                    symbol: partySymbol,
                    customizationPresetId: 0
                }),
                creatorFeeOn: true,
                a: 50_000,
                b: 0.001 ether
            }),
            METADATA_PROVIDER,
            abi.encode(metadata),
            uint80(initialMembers.length + 1) // Initial members + host
        );

        // Distribute cards to all members.
        party.transferFrom(address(this), host, 1);
        for (uint256 i = 0; i < initialMembers.length; i++) {
            uint256 tokenId = i + 2;
            party.transferFrom(address(this), initialMembers[i], tokenId);
        }

        // Refund excess ETH
        if (address(this).balance > 0) {
            (bool success, bytes memory res) = msg.sender.call{ value: address(this).balance }("");
            if (!success) {
                // Bubble up revert reasons from plugins
                assembly ("memory-safe") {
                    revert(add(res, 32), mload(res))
                }
            }
        }

        emit EZPartyCreated(party, host, initialMembers);
    }

    receive() external payable {}
}
