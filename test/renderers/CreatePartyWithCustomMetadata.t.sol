// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { Party } from "../../contracts/party/Party.sol";
import { MetadataProvider } from "../../contracts/renderers/MetadataProvider.sol";
import { BasicMetadataProvider } from "../../contracts/renderers/BasicMetadataProvider.sol";
import { SSTORE2MetadataProvider } from "../../contracts/renderers/SSTORE2MetadataProvider.sol";
import { PartyNFTRenderer } from "../../contracts/renderers/PartyNFTRenderer.sol";

contract CreatePartyWithCustomMetadataTest is SetupPartyHelper {
    MetadataProvider metadataProvider;
    BasicMetadataProvider basicMetadataProvider;
    SSTORE2MetadataProvider sstore2MetadataProvider;

    constructor() SetupPartyHelper(false) {}

    function setUp() public override {
        super.setUp();

        metadataProvider = new MetadataProvider(globals);
        basicMetadataProvider = new BasicMetadataProvider(globals);
        sstore2MetadataProvider = new SSTORE2MetadataProvider(globals);
    }

    function createParty_withCustomMetadata(PartyNFTRenderer.Metadata memory metadata) public {
        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        Party.PartyOptions memory opts;
        address[] memory hosts = new address[](1);
        hosts[0] = address(420);
        opts.name = "PARTY";
        opts.symbol = "PR-T";
        opts.governance.hosts = hosts;
        opts.governance.voteDuration = 99;
        opts.governance.executionDelay = 1000;
        opts.governance.passThresholdBps = 1000;
        opts.governance.totalVotingPower = johnVotes + dannyVotes + steveVotes + thisVotes;

        uint256 gas = gasleft();

        party = partyFactory.createPartyWithMetadata(
            partyImpl,
            authorities,
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            sstore2MetadataProvider,
            abi.encode(metadata)
        );

        emit log_named_uint("gas used SSTORE2", gas - gasleft());

        gas = gasleft();

        party = partyFactory.createPartyWithMetadata(
            partyImpl,
            authorities,
            opts,
            preciousTokens,
            preciousTokenIds,
            0,
            basicMetadataProvider,
            abi.encode(metadata)
        );
        emit log_named_uint("gas used basic", gas - gasleft());

        bytes memory metadata = basicMetadataProvider.getMetadata(address(party), 0);

        PartyNFTRenderer.Metadata memory decodedMetadata = abi.decode(
            metadata,
            (PartyNFTRenderer.Metadata)
        );
    }

    function testRunMetadataBenchmarkShortLinks() public {
        string memory description = "this is my desciption!";
        for (uint i = 0; i < 10; ++i) {
            emit log(string.concat("Description is now: ", description));
            createParty_withCustomMetadata(
                PartyNFTRenderer.Metadata({
                    name: "My Party!",
                    description: description,
                    externalURL: "https://shortlink.io",
                    image: "https://shortlink.io",
                    banner: "",
                    animationURL: "https://shortlink.io",
                    collectionName: "My Party!",
                    collectionDescription: description,
                    collectionExternalURL: "",
                    royaltyReceiver: _randomAddress(),
                    royaltyAmount: _randomUint256(),
                    renderingMethod: PartyNFTRenderer.RenderingMethod.ENUM_OFFSET
                })
            );
            description = string.concat(description, "adding some amazing fluff here!!");
        }
    }

    function testRunMetadataBenchmark() public {
        string memory description = "this is my desciption!";
        for (uint i = 0; i < 10; ++i) {
            emit log(string.concat("Description is now: ", description));
            createParty_withCustomMetadata(
                PartyNFTRenderer.Metadata({
                    name: "My Party!",
                    description: description,
                    externalURL: "ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq",
                    image: "ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq",
                    banner: "",
                    animationURL: "ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq",
                    collectionName: "My Party!",
                    collectionDescription: description,
                    collectionExternalURL: "",
                    royaltyReceiver: _randomAddress(),
                    royaltyAmount: _randomUint256(),
                    renderingMethod: PartyNFTRenderer.RenderingMethod.ENUM_OFFSET
                })
            );
            description = string.concat(description, "adding some amazing fluff here!!");
        }
    }
}
