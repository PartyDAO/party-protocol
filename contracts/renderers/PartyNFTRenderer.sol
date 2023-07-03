// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../utils/LibSafeCast.sol";
import "../utils/vendor/Strings.sol";
import "../utils/vendor/Base64.sol";

import "./RendererBase.sol";
import "./MetadataRegistry.sol";
import "./IMetadataRegistry1_1.sol";
import "../party/PartyGovernance.sol";
import "../party/PartyGovernanceNFT.sol";
import "../distribution/TokenDistributor.sol";

contract PartyNFTRenderer is RendererBase {
    using LibSafeCast for uint256;
    using Strings for uint256;
    using Strings for address;

    error InvalidTokenIdError();

    struct ProposalData {
        uint256 id;
        string status;
    }

    struct Metadata {
        string description;
        string externalURL;
        string image;
        string banner;
        string collectionName;
        string collectionDescription;
        string collectionExternalURL;
        address royaltyReceiver;
        uint256 royaltyAmount;
    }

    uint256 constant PARTY_CARD_DATA = 1;
    address constant PARTYSTAR_PARTY_ADDRESS = 0x118928CCAc2035B578ae2D35FBFc2c120B6c4B82;
    address constant PARTYSTAR_CROWDFUND_ADDRESS = 0x0Bf08f7b6474C2aCCB9b9e325acb6FbcC682dE82;
    IMetadataRegistry1_1 constant OLD_METADATA_REGISTRY =
        IMetadataRegistry1_1(0x175487875F0318EdbAB54BBA442fF53b36e96015);

    constructor(
        IGlobals globals,
        RendererStorage rendererStorage,
        IFont font
    ) RendererBase(globals, rendererStorage, font) {}

    function royaltyInfo(
        uint256,
        uint256
    ) external view returns (address receiver, uint256 royaltyAmount) {
        // Get any custom metadata for this party.
        Metadata memory metadata = getCustomMetadata();

        // By default, there are no royalties.
        return (metadata.royaltyReceiver, metadata.royaltyAmount);
    }

    function contractURI() external view override returns (string memory) {
        (bool isDarkMode, Color color) = getCustomizationChoices();
        (string memory image, string memory banner) = getCollectionImageAndBanner(
            color,
            isDarkMode
        );

        // Get any custom metadata for this party.
        Metadata memory metadata = getCustomMetadata();

        return
            string.concat(
                "data:application/json;base64,",
                Base64.encode(
                    abi.encodePacked(
                        '{"name":"',
                        bytes(metadata.collectionName).length == 0
                            ? generateCollectionName()
                            : metadata.collectionName,
                        '", "description":"',
                        bytes(metadata.collectionDescription).length == 0
                            ? generateCollectionDescription()
                            : metadata.collectionDescription,
                        '", "external_url":"',
                        bytes(metadata.collectionExternalURL).length == 0
                            ? generateExternalURL()
                            : metadata.collectionExternalURL,
                        '", "image":"',
                        bytes(metadata.image).length == 0 ? image : metadata.image,
                        '", "banner":"',
                        bytes(metadata.banner).length == 0 ? banner : metadata.banner,
                        '"}'
                    )
                )
            );
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (PartyGovernanceNFT(address(this)).ownerOf(tokenId) == address(0)) {
            revert InvalidTokenIdError();
        }

        // Add backward compatibility for rendering custom metadata for
        // Partystar party using old `MetadataRegistry` contract.
        if (address(this) == PARTYSTAR_PARTY_ADDRESS) {
            (
                string memory customName,
                string memory customDescription,
                string memory customImage
            ) = OLD_METADATA_REGISTRY.customPartyMetadataByCrowdfund(PARTYSTAR_CROWDFUND_ADDRESS);

            return
                string.concat(
                    "data:application/json;base64,",
                    Base64.encode(
                        abi.encodePacked(
                            '{"name":"',
                            string.concat(customName, " #", tokenId.toString()),
                            '", "description":"',
                            customDescription,
                            '", "external_url":"',
                            generateExternalURL(),
                            '", "attributes": [',
                            generateAttributes(tokenId),
                            '], "image":"',
                            customImage,
                            '"}'
                        )
                    )
                );
        }

        // Get any custom metadata for this party.
        Metadata memory metadata = getCustomMetadata();

        // Construct metadata.
        if (hasPartyStarted()) {
            return
                string.concat(
                    "data:application/json;base64,",
                    Base64.encode(
                        abi.encodePacked(
                            '{"name":"',
                            generateName(tokenId),
                            '", "description":"',
                            bytes(metadata.description).length == 0
                                ? generateDescription(
                                    PartyGovernanceNFT(address(this)).name(),
                                    tokenId
                                )
                                : metadata.description,
                            '", "external_url":"',
                            bytes(metadata.externalURL).length == 0
                                ? generateExternalURL()
                                : metadata.externalURL,
                            '", "attributes": [',
                            generateAttributes(tokenId),
                            '], "image":"',
                            bytes(metadata.image).length == 0
                                ? generateSVG(
                                    PartyGovernanceNFT(address(this)).name(),
                                    generateVotingPowerPercentage(tokenId),
                                    getLatestProposalStatuses(),
                                    PartyGovernance(address(this)).lastProposalId(),
                                    tokenId,
                                    hasUnclaimedDistribution(tokenId)
                                )
                                : metadata.image,
                            '"}'
                        )
                    )
                );
        } else {
            return
                string.concat(
                    "data:application/json;base64,",
                    Base64.encode(
                        abi.encodePacked(
                            '{"name":"',
                            generateName(tokenId),
                            '", "description":"',
                            bytes(metadata.description).length == 0
                                ? generateDescription(
                                    PartyGovernanceNFT(address(this)).name(),
                                    tokenId
                                )
                                : metadata.description,
                            '", "external_url":"',
                            bytes(metadata.externalURL).length == 0
                                ? generateExternalURL()
                                : metadata.externalURL,
                            '", "image":"',
                            bytes(metadata.image).length == 0
                                ? generateSVG(
                                    PartyGovernanceNFT(address(this)).name(),
                                    generateVotingPowerPercentage(tokenId),
                                    getLatestProposalStatuses(),
                                    PartyGovernance(address(this)).lastProposalId(),
                                    tokenId,
                                    hasUnclaimedDistribution(tokenId)
                                )
                                : metadata.image,
                            '"}'
                        )
                    )
                );
        }
    }

    function generateName(uint256 tokenId) private view returns (string memory) {
        if (hasPartyStarted()) {
            return string.concat(generateVotingPowerPercentage(tokenId), "% Voting Power");
        } else {
            return "Party Membership";
        }
    }

    function generateExternalURL() private view returns (string memory) {
        return string.concat("https://party.app/party/", address(this).toHexString());
    }

    function generateDescription(
        string memory partyName,
        uint256 tokenId
    ) private view returns (string memory) {
        if (hasPartyStarted()) {
            return
                string.concat(
                    "This membership represents ",
                    generateVotingPowerPercentage(tokenId),
                    "% voting power in ",
                    partyName,
                    ". Head to ",
                    generateExternalURL(),
                    " to view the Party's latest activity."
                );
        } else {
            return
                string.concat(
                    "This item represents membership in ",
                    partyName,
                    ". Exact voting power will be determined when the crowdfund ends. Head to ",
                    generateExternalURL(),
                    " to view the Party's latest activity."
                );
        }
    }

    function generateAttributes(uint256 tokenId) private view returns (string memory) {
        string memory votingPowerPercentage = generateVotingPowerPercentage(tokenId);

        if (
            keccak256(abi.encodePacked(votingPowerPercentage)) == keccak256(abi.encodePacked("--"))
        ) {
            votingPowerPercentage = "0";
        }

        return
            string.concat(
                '{"trait_type":"Voting Power", "value":',
                votingPowerPercentage,
                ', "max_value":100}'
            );
    }

    function generateCollectionName() internal view returns (string memory) {
        return string.concat("Party Memberships: ", PartyGovernanceNFT(address(this)).name());
    }

    function generateCollectionDescription() internal view returns (string memory) {
        return
            string.concat(
                "This collection represents memberships in the following Party: ",
                PartyGovernanceNFT(address(this)).name(),
                ". Head to ",
                generateExternalURL(),
                " to view the Party's latest activity."
            );
    }

    function generateSVG(
        string memory partyName,
        string memory votingPowerPercentage,
        PartyGovernance.ProposalStatus[4] memory proposalStatuses,
        uint256 latestProposalId,
        uint256 tokenId,
        bool hasUnclaimed
    ) public view returns (string memory) {
        // Get the customization data for this party.
        (bool isDarkMode, Color color) = getCustomizationChoices();

        return
            generateSVG(
                partyName,
                votingPowerPercentage,
                proposalStatuses,
                latestProposalId,
                tokenId,
                hasUnclaimed,
                color,
                isDarkMode
            );
    }

    function generateSVG(
        string memory partyName,
        string memory votingPowerPercentage,
        PartyGovernance.ProposalStatus[4] memory proposalStatuses,
        uint256 latestProposalId,
        uint256 tokenId,
        bool hasUnclaimed,
        Color color,
        bool isDarkMode
    ) public view returns (string memory) {
        return
            string.concat(
                "data:image/svg+xml;base64,",
                Base64.encode(
                    abi.encodePacked(
                        // Split to avoid stack too deep errors
                        generateSVG1(color, isDarkMode),
                        generateSVG2(partyName, color),
                        generateSVG3(partyName, color),
                        generateSVG4(
                            latestProposalId,
                            proposalStatuses,
                            votingPowerPercentage,
                            color
                        ),
                        generateSVG5(hasUnclaimed, tokenId, color)
                    )
                )
            );
    }

    function generateSVG1(Color color, bool isDarkMode) private pure returns (string memory) {
        return
            string.concat(
                '<svg width="540" height="540" viewBox="0 -10 360 560" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><defs><linearGradient id="d" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="',
                isDarkMode ? "#2e3847" : "#ffffff",
                '"/><stop offset="1" stop-color="',
                isDarkMode ? "#000000" : "#e6edf5",
                '"/></linearGradient><linearGradient id="e" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="',
                isDarkMode ? "#8091a8" : "#e6edf6",
                '"/><stop offset="1" stop-color="',
                isDarkMode ? "#2e3848" : "#bccbdd",
                '"/></linearGradient><linearGradient id="f" x1="0" x2="0" y1="1" y2="0"><stop offset="0" stop-color="',
                generateColorHex(color, ColorType.SECONDARY),
                '"/><stop offset="1" stop-color="',
                generateColorHex(color, ColorType.PRIMARY),
                '"/></linearGradient><linearGradient id="f2" x1="0" x2="0" y1="-.5" y2="1"><stop offset="0" stop-color="',
                generateColorHex(color, ColorType.SECONDARY),
                '"/><stop offset="1" stop-color="',
                generateColorHex(color, ColorType.PRIMARY),
                '"/></linearGradient><linearGradient id="h" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="',
                isDarkMode ? "#ffffff" : "#3f485f",
                '"/><stop offset=".5"  stop-color="',
                isDarkMode ? "#a7b8cf" : "#000000",
                '"/></linearGradient><radialGradient cx="1" cy="-.5" id="i" r="2"><stop offset="0" stop-color="#dce5f0"/><stop offset=".5" stop-color="#dce5f0" stop-opacity="0"/></radialGradient>'
            );
    }

    function generateSVG2(
        string memory partyName,
        Color color
    ) private view returns (string memory) {
        (
            uint256 duration,
            uint256 steps,
            uint256 delay,
            uint256 translateX
        ) = calcAnimationVariables(partyName);

        return
            string.concat(
                '<symbol id="a" viewBox="0 0 300.15 300"><path d="M6.07 0v300m-3-300v300M.07 0v300m9-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300" style="stroke-width:.15px;stroke:',
                generateColorHex(color, ColorType.PRIMARY),
                ';fill:none;0"/></symbol><style>.z{animation:x ',
                duration.toString(),
                "s steps(",
                steps.toString(),
                ") infinite;}.y{animation-delay:",
                delay.toString(),
                "s}@keyframes x{to{transform:translateX(-",
                translateX.toString(),
                "px)}}.v{fill:",
                generateColorHex(color, ColorType.DARK),
                ";font-family:pixeldroidConsoleRegular,Console;font-size:48px}.w{animation:W 1s steps(1, jump-end) infinite;}@keyframes W{50%{fill:",
                generateColorHex(color, ColorType.LIGHT),
                "}}@font-face{font-family:pixeldroidConsoleRegular;src:url(",
                _font.getFont(),
                ");}</style></defs>"
            );
    }

    function generateSVG3(
        string memory partyName,
        Color color
    ) private pure returns (string memory) {
        return
            string.concat(
                '<rect height="539" rx="29.5" ry="29.5" style="fill:url(#d);stroke:url(#e)" width="359" x=".5" y=".5"/><rect rx="15.5" ry="15.5" style="stroke:url(#f);fill:',
                generateColorHex(color, ColorType.PRIMARY),
                '" width="331" height="346" x="14.5" y="179.5"/><path d="M321 501H198v-27h123v27Zm9-282H30v27h300v-27Zm0 60H30v27h300v-27Zm0 30H30v27h300v-27Zm0 30H30v27h300v-27Zm0 30H30v27h300v-27Z" style="fill:',
                generateColorHex(color, ColorType.LIGHT),
                ';"/><clipPath id="clip"><path d="M31 501H198v-27h123v27Zm9-282H30v27h300v-27Zm0"/></clipPath><g clip-path="url(#clip)"><g class="z"><text class="v" x="327" y="240">',
                partyName,
                '</text></g><g class="z y"><text class="v" x="327" y="240">',
                partyName,
                "</text></g></g>"
            );
    }

    function generateSVG4(
        uint256 latestProposalId,
        PartyGovernance.ProposalStatus[4] memory proposalStatuses,
        string memory votingPowerPercentage,
        Color color
    ) private pure returns (string memory) {
        return
            string.concat(
                '<text class="v" x="30" y="300">',
                latestProposalId > 0
                    ? generateProposalStatus(latestProposalId, proposalStatuses[0])
                    : "",
                '</text><text class="v" x="30" y="330">',
                latestProposalId > 1
                    ? generateProposalStatus(latestProposalId - 1, proposalStatuses[1])
                    : "",
                '</text><text class="v" x="30" y="360">',
                latestProposalId > 2
                    ? generateProposalStatus(latestProposalId - 2, proposalStatuses[2])
                    : "",
                '</text><text class="v" x="30" y="390">',
                latestProposalId > 3
                    ? generateProposalStatus(latestProposalId - 3, proposalStatuses[3])
                    : "",
                '</text><text class="v" x="201" y="495">',
                votingPowerPercentage,
                '</text><text class="v" x="297" y="495">%</text>'
                '<use height="300" x="30" y="210" width="300.15" xlink:href="#a"/><use height="300" transform="rotate(-90 270 240)" width="300.15" xlink:href="#a"/><rect rx="3.5" ry="3.5" style="fill:none;stroke:',
                generateColorHex(color, ColorType.DARK),
                ';stroke-width:3px" width="138" height="42" x="190.5" y="466.5"/><path fill="',
                generateColorHex(color, ColorType.DARK)
            );
    }

    function generateSVG5(
        bool hasUnclaimed,
        uint256 tokenId,
        Color color
    ) private view returns (string memory) {
        return
            string.concat(
                '"',
                _storage.readFile(PARTY_CARD_DATA),
                '<path d="M285 164c-7.72 0-14-6.28-14-14s6.28-14 14-14h45c7.72 0 14 6.28 14 14s-6.28 14-14 14h-45Z" style="fill:none;stroke:',
                generateColorHex(color, ColorType.PRIMARY),
                ';stroke-width:2px"/><path d="M307.5 68.19c-20.71 0-37.5 11.6-37.5 25.91s16.79 25.91 37.5 25.91S345 108.41 345 94.1s-16.79-25.91-37.5-25.91Zm12.84 41.66v-7.31l9.74-3.17-25.51-8.29 14.01 19.28a43.35 43.35 0 0 1-20.64.38v-8.33l9.74-3.17-25.51-8.29 14.06 19.35c-10.92-3-18.63-10.23-18.63-18.68 0-6.22 4.17-11.78 10.73-15.48l14.24 19.6V85.5l9.74-3.17-22.07-7.17a40.24 40.24 0 0 1 17.25-3.7c11.3 0 21.13 4.23 26.21 10.47l-23.17-7.53 15.76 21.7V85.86l8.32-2.7a14.9 14.9 0 0 1 2.77 8.48c0 8.04-6.97 14.98-17.05 18.22Z" style="fill:#A7B8CF"/><clipPath id="C"><path d="m98.43 483.54 1.39 5.02h-3.77l1.42-5.02.38-2.02h.17l.41 2.02ZM171 470v35a5 5 0 0 1-5 5H35a5 5 0 0 1-5-5v-35a5 5 0 0 1 5-5h131a5 5 0 0 1 5 5Zm-93.49 10.56c-1.71-1.4-3.1-2.06-5.5-2.06-3.82 0-7.39 3.19-7.39 8.64 0 6.35 3.17 9.36 7.34 9.36 2.4 0 4.12-.82 5.47-2.47v-4.06c-1.06 1.58-2.35 2.95-4.54 2.95-3.19 0-4.13-3.44-4.13-5.38 0-3.42 1.76-4.94 4.1-4.94 1.78 0 3.26.71 4.63 2.93v-4.97Zm11.28 11.81h-4.36v-13.54h-4.25v17.3h8.61v-3.77Zm17.27 3.77-5.06-17.3h-6.1l-5.09 17.3h4.27l1.06-4.06h5.59l1.06 4.06h4.27Zm6.21-17.3H108v17.3h4.27v-17.3Zm22.1 0h-6.39l-2.45 9.73-.28 3.64h-.24l-.32-3.67-2.46-9.71h-6.39v17.3h4.15v-10.44c0-.38-.1-2.16-.17-3.07h.24l3.07 13.51h3.96l3.07-13.51h.24l-.19 3.07v10.44h4.15v-17.3Z" /></clipPath><g clip-path="url(#C)"><rect class="w" x="30" y="465" width="142" height="50" fill="',
                hasUnclaimed
                    ? generateColorHex(color, ColorType.DARK)
                    : generateColorHex(color, ColorType.LIGHT),
                '"/></g><rect height="345" rx="15" ry="15" style="fill:url(#i)" width="330" x="15" y="180"/><text text-anchor="middle" style="font-family:ui-monospace,Cascadia Mono,Menlo,Monaco,Segoe UI Mono,Roboto Mono,Oxygen Mono,Ubuntu Monospace,Source Code Pro,Droid Sans Mono,Fira Mono,Courier,monospace;fill:',
                generateColorHex(color, ColorType.PRIMARY),
                ';font-weight:500;" x="307.5" y="156">',
                // Always render token ID with 3 digits.
                prependNumWithZeros(tokenId.toString(), 3),
                "</text></svg>"
            );
    }

    function generateProposalStatus(
        uint256 proposalId,
        PartyGovernance.ProposalStatus status
    ) private pure returns (string memory) {
        string memory statusMessage;
        if (status == PartyGovernance.ProposalStatus.Voting) {
            statusMessage = "Voting now";
        } else if (status == PartyGovernance.ProposalStatus.Passed) {
            statusMessage = "Passing";
        } else if (status == PartyGovernance.ProposalStatus.Ready) {
            statusMessage = "Executable";
        } else if (status == PartyGovernance.ProposalStatus.InProgress) {
            statusMessage = "In progress";
        } else if (status == PartyGovernance.ProposalStatus.Complete) {
            statusMessage = "Complete";
        } else if (status == PartyGovernance.ProposalStatus.Defeated) {
            statusMessage = "Defeated";
        } else if (status == PartyGovernance.ProposalStatus.Cancelled) {
            statusMessage = "Cancelled";
        } else {
            return "";
        }

        return string.concat("#", proposalId.toString(), " - ", statusMessage);
    }

    function generateVotingPowerPercentage(uint256 tokenId) private view returns (string memory) {
        Party party = Party(payable(address(this)));
        uint256 totalVotingPower = party.getGovernanceValues().totalVotingPower;

        if (totalVotingPower == 0) {
            return "--";
        }

        uint256 intrinsicVotingPowerPercentage = (party.votingPowerByTokenId(tokenId) * 1e18) /
            totalVotingPower;

        if (intrinsicVotingPowerPercentage == 1e18) {
            return "100";
        } else if (intrinsicVotingPowerPercentage < 0.1e18) {
            return formatAsDecimalString(intrinsicVotingPowerPercentage, 16, 3);
        } else {
            return formatAsDecimalString(intrinsicVotingPowerPercentage, 16, 4);
        }
    }

    function getCustomMetadata() private view returns (Metadata memory metadata) {
        MetadataRegistry registry = MetadataRegistry(
            _GLOBALS.getAddress(LibGlobals.GLOBAL_METADATA_REGISTRY)
        );

        bytes memory encodedMetadata = registry.getMetadata(address(this));
        return encodedMetadata.length != 0 ? abi.decode(encodedMetadata, (Metadata)) : metadata;
    }

    function getLatestProposalStatuses()
        private
        view
        returns (PartyGovernance.ProposalStatus[4] memory proposalStatuses)
    {
        uint16 versionId = getPartyVersion();
        uint256 latestProposalId = PartyGovernance(address(this)).lastProposalId();
        uint256 numOfProposalsToDisplay = latestProposalId < 4 ? latestProposalId : 4;
        for (uint256 i; i < numOfProposalsToDisplay; ++i) {
            uint256 proposalId = latestProposalId - i;

            uint16 status;
            if (versionId == 0) {
                IParty1_1.ProposalStatus proposalStatus;
                (proposalStatus, ) = IParty1_1(address(this)).getProposalStateInfo(proposalId);
                status = uint16(proposalStatus);
            } else {
                PartyGovernance.ProposalStatus proposalStatus;
                (proposalStatus, ) = PartyGovernance(address(this)).getProposalStateInfo(
                    proposalId
                );
                status = uint16(proposalStatus);
            }

            proposalStatuses[i] = PartyGovernance.ProposalStatus(status);
        }
    }

    function getPartyVersion() private view returns (uint16) {
        (bool success, bytes memory response) = address(this).staticcall(
            abi.encodeCall(Party(payable(address(this))).VERSION_ID, ())
        );

        if (!success) return 0;

        return abi.decode(response, (uint16));
    }

    function hasUnclaimedDistribution(uint256 tokenId) private view returns (bool) {
        TokenDistributor[] memory distributors = new TokenDistributor[](2);
        distributors[0] = TokenDistributor(
            _GLOBALS.getAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR)
        );
        // Address of the old token distributor contract.
        distributors[1] = TokenDistributor(0x1CA2007a81F8A7491BB6E11D8e357FD810896454);

        Party party = Party(payable(address(this)));
        for (uint256 i; i < distributors.length; ++i) {
            TokenDistributor distributor = distributors[i];
            uint256 lastDistributionId = distributor.lastDistributionIdPerParty(party);

            for (
                uint256 distributionId = 1;
                distributionId <= lastDistributionId;
                ++distributionId
            ) {
                if (!distributor.hasPartyTokenIdClaimed(party, tokenId, distributionId)) {
                    return true;
                }
            }
        }

        return false;
    }

    function hasPartyStarted() private view returns (bool) {
        uint256 totalVotingPower = PartyGovernance(address(this))
            .getGovernanceValues()
            .totalVotingPower;

        return totalVotingPower != 0;
    }

    function calcAnimationVariables(
        string memory partyName
    ) private pure returns (uint256 duration, uint256 steps, uint256 delay, uint256 translateX) {
        translateX = bytes(partyName).length * 30 + 300;
        duration = translateX / 56;
        if (duration % 2 != 0) {
            // Make duration even so that the animation delay is always exactly
            // half of the duration.
            duration += 1;
        }
        delay = duration / 2;
        steps = translateX / 6;
    }
}
