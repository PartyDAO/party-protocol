// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.17;

import "../utils/LibSafeCast.sol";
import "../utils/vendor/Strings.sol";
import "../utils/vendor/Base64.sol";

import "./IERC721Renderer.sol";
import "./RendererCustomization.sol";
import "../globals/IGlobals.sol";
import "../party/PartyGovernance.sol";
import "../party/PartyGovernanceNFT.sol";
import "../distribution/TokenDistributor.sol";
import "./RendererStorage.sol";
import "./fonts/IFont.sol";

contract PartyNFTRenderer is IERC721Renderer, RendererCustomization {
    using LibSafeCast for uint256;
    using Strings for uint256;
    using Strings for address;

    error InvalidTokenIdError();

    struct ProposalData {
        uint256 id;
        string status;
    }

    uint256 constant PARTY_CARD_DATA = 1;

    IGlobals private immutable _GLOBALS;
    RendererStorage private immutable _storage;
    IFont private immutable _font;

    constructor(IGlobals globals, RendererStorage rendererStorage, IFont font)
        RendererCustomization(rendererStorage)
    {
        _GLOBALS = globals;
        _storage = rendererStorage;
        _font = font;
    }

    // The renderer is called via delegateCall, so we need to declare the storage layout.
    // Run `yarn layout Party.sol/Party` to generate the current layout.
    bool emergencyExecuteDisabled;
    uint16 feeBps;
    address payable feeRecipient;
    bytes32 preciousListHash;
    uint256 lastProposalId;
    mapping(address => bool) isHost;
    mapping(address => address) delegationsByVoter;
    PartyGovernance.GovernanceValues _governanceValues;
    mapping(uint256 => PartyGovernance.ProposalState) _proposalStateByProposalId;
    mapping(address => PartyGovernance.VotingPowerSnapshot[]) _votingPowerSnapshotsByVoter;
    string name;
    string symbol;
    mapping(uint256 => address) _ownerOf;
    mapping(address => uint256) _balanceOf;
    mapping(uint256 => address) getApproved;
    mapping(address => mapping(address => bool)) isApprovedForAll;
    address mintAuthority;
    uint256 tokenCount;
    mapping(uint256 => uint256) votingPowerByTokenId;

    // TODO: Implement contract URI
    function contractURI() external view returns (string memory) {
        string memory json = Base64.encode(bytes(
            string(
                abi.encodePacked(
                    '{"name":"',
                    name,
                    '", "description":"',
                    "AuctionCrowdfund Governance NFTs give you voting power in a AuctionCrowdfund party.",
                    // '", "image": "data:image/svg+xml;base64,',
                    // Base64.encode(bytes(output)),
                    '"}'
                )
            )
        ));

        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    function royaltyInfo(uint256, uint256)
        external
        pure
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = address(0);
        royaltyAmount = 0;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if(_ownerOf[tokenId] == address(0)) {
            revert InvalidTokenIdError();
        }

        // Get the customization data for this crowdfund.
        (bool isDarkMode, Color color) = getCustomizationChoices();

        // Construct metadata.
        return string.concat(
            'data:application/json;base64,',
            Base64.encode(abi.encodePacked(
                '{"name":"',
                generateName(tokenId),
                '", "description":"',
                generateDescription(tokenId),
                '", "external_url":"',
                generateExternalURL(),
                '", "attributes": [',
                generateAttributes(tokenId),
                '], "image": "data:image/svg+xml;base64,',
                Base64.encode(abi.encodePacked(
                    // Split to avoid stack too deep errors
                    generateSVG1(color, isDarkMode),
                    generateSVG2(color),
                    generateSVG3(color),
                    generateSVG4(color, tokenId),
                    generateSVG5(color, tokenId)
                )),
                '"}'
            ))
        );
    }

    function generateName(uint256 tokenId) private view returns (string memory) {
        return string.concat(name, ' Card #', tokenId.toString());
    }

    function generateExternalURL() private view returns (string memory) {
        return string.concat('https://partybid.app/party/', address(this).toHexString());
    }

    function generateDescription(uint256 tokenId) private view returns (string memory) {
        return string.concat(
            'Card #',
            tokenId.toString(),
            ' in ',
            name,
            ". This item represents ",
            generateVotingPowerPercentage(tokenId),
            '% membership in the party. Head to ',
            generateExternalURL(),
            " to view the party's latest activity."
        );
    }

    function generateAttributes(uint256 tokenId) private view returns (string memory) {
        return string.concat(
            '{"trait_type":"Voting Power", "value":',
            generateVotingPowerPercentage(tokenId),
            ', "max_value":100}'
        );
    }

    function generateSVG1(Color color, bool isDarkMode) private pure returns (string memory) {
        return string.concat(
            '<svg viewBox="0 0 360 540" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><defs><linearGradient id="d" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="',
            isDarkMode ? '#2e3847' : '#ffffff',
            '"/><stop offset="1" stop-color="',
            isDarkMode ? '#000000' : '#e6edf5',
            '"/></linearGradient><linearGradient id="e" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="',
            isDarkMode ? '#8091a8' : '#e6edf6',
            '"/><stop offset="1" stop-color="',
            isDarkMode ? '#2e3848' : '#bccbdd',
            '"/></linearGradient><linearGradient id="f" x1="0" x2="0" y1="1" y2="0"><stop offset="0" stop-color="',
            generateColorHex(color, ColorType.SECONDARY),
            '"/><stop offset="1" stop-color="',
            generateColorHex(color, ColorType.PRIMARY),
            '"/></linearGradient><linearGradient id="f2" x1="0" x2="0" y1="-.5" y2="1"><stop offset="0" stop-color="',
            generateColorHex(color, ColorType.SECONDARY),
            '"/><stop offset="1" stop-color="',
            generateColorHex(color, ColorType.PRIMARY),
            '"/></linearGradient><linearGradient id="h" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="',
            isDarkMode ? '#ffffff' : '#3f485f',
            '"/><stop offset=".5"  stop-color="',
            isDarkMode ? '#a7b8cf' : '#000000',
            '"/></linearGradient><radialGradient cx="1" cy="-.5" id="i" r="2"><stop offset="0" stop-color="#dce5f0"/><stop offset=".5" stop-color="#dce5f0" stop-opacity="0"/></radialGradient>'
        );
    }

    function generateSVG2(Color color) private view returns (string memory) {
        (uint256 duration, uint256 steps, uint256 delay, uint256 translateX) = calcAnimationVariables();

        return string.concat(
            '<symbol id="a" viewBox="0 0 300.15 300"><path d="M6.07 0v300m-3-300v300M.07 0v300m9-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300m3-300v300" style="stroke-width:.15px;stroke:',
            generateColorHex(color, ColorType.PRIMARY),
            ';fill:none;0"/></symbol><style>.z{animation:x ',
            duration.toString(),
            's steps(',
            steps.toString(),
            ') infinite;}.y{animation-delay:',
            delay.toString(),
            's}@keyframes x{to{transform:translateX(-',
            translateX.toString(),
            'px)}}.v{fill:',
            generateColorHex(color, ColorType.DARK),
            ';font-family:pixeldroidConsoleRegular,Console;font-size:48px}@font-face{font-family:pixeldroidConsoleRegular;src:url(',
            _font.getFont(),
            ');}</style></defs>'
        );
    }

    function generateSVG3(Color color) private view returns (string memory) {
        return string.concat(
            '<rect height="539" rx="29.5" ry="29.5" style="fill:url(#d);stroke:url(#e)" width="359" x=".5" y=".5"/><rect rx="15.5" ry="15.5" style="stroke:url(#f);fill:',
            generateColorHex(color, ColorType.PRIMARY),
            '" width="331" height="346" x="14.5" y="179.5"/><path d="M321 501H198v-27h123v27Zm9-282H30v27h300v-27Zm0 60H30v27h300v-27Zm0 30H30v27h300v-27Zm0 30H30v27h300v-27Zm0 30H30v27h300v-27Z" style="fill:',
            generateColorHex(color, ColorType.LIGHT),
            ';"/><clipPath id="clip"><path d="M31 501H198v-27h123v27Zm9-282H30v27h300v-27Zm0"/></clipPath><g clip-path="url(#clip)"><text class="v z" x="327" y="240">',
            name,
            '</text><text class="v z y" x="327" y="240">',
            name,
            '</text></g>'
        );
    }

    function generateSVG4(Color color, uint256 tokenId) private view returns (string memory) {
        string[4] memory latestProposalStatuses = getLatestProposalStatuses();

        return string.concat(
            '<text class="v" x="30" y="300">',
            latestProposalStatuses[0],
            '</text><text class="v" x="30" y="330">',
            latestProposalStatuses[1],
            '</text><text class="v" x="30" y="360">',
            latestProposalStatuses[2],
            '</text><text class="v" x="30" y="390">',
            latestProposalStatuses[3],
            '</text><text class="v" x="201" y="495">',
            generateVotingPowerPercentage(tokenId),
            '</text><text class="v" x="297" y="495">%</text>'
            '<use height="300" x="30" y="210" width="300.15" xlink:href="#a"/><use height="300" transform="rotate(-90 270 240)" width="300.15" xlink:href="#a"/><rect rx="3.5" ry="3.5" style="fill:none;stroke:',
            generateColorHex(color, ColorType.DARK),
            ';stroke-width:3px" width="138" height="42" x="190.5" y="466.5"/><path fill="',
            generateColorHex(color, ColorType.DARK)
        );
    }

    function generateSVG5(Color color, uint256 tokenId) private view returns (string memory) {
        return string.concat(
            '"',
            _storage.readFile(PARTY_CARD_DATA),
            '<path d="M285 164c-7.72 0-14-6.28-14-14s6.28-14 14-14h45c7.72 0 14 6.28 14 14s-6.28 14-14 14h-45Z" style="fill:none;stroke:',
            generateColorHex(color, ColorType.PRIMARY),
            ';stroke-width:2px"/><path d="M307.5 68.19c-20.71 0-37.5 11.6-37.5 25.91s16.79 25.91 37.5 25.91S345 108.41 345 94.1s-16.79-25.91-37.5-25.91Zm12.84 41.66v-7.31l9.74-3.17-25.51-8.29 14.01 19.28a43.35 43.35 0 0 1-20.64.38v-8.33l9.74-3.17-25.51-8.29 14.06 19.35c-10.92-3-18.63-10.23-18.63-18.68 0-6.22 4.17-11.78 10.73-15.48l14.24 19.6V85.5l9.74-3.17-22.07-7.17a40.24 40.24 0 0 1 17.25-3.7c11.3 0 21.13 4.23 26.21 10.47l-23.17-7.53 15.76 21.7V85.86l8.32-2.7a14.9 14.9 0 0 1 2.77 8.48c0 8.04-6.97 14.98-17.05 18.22Z" style="fill:',
            generateColorHex(color, ColorType.PRIMARY),
            '"/><path d="m98.43 483.54 1.39 5.02h-3.77l1.42-5.02.38-2.02h.17l.41 2.02ZM171 470v35a5 5 0 0 1-5 5H35a5 5 0 0 1-5-5v-35a5 5 0 0 1 5-5h131a5 5 0 0 1 5 5Zm-93.49 10.56c-1.71-1.4-3.1-2.06-5.5-2.06-3.82 0-7.39 3.19-7.39 8.64 0 6.35 3.17 9.36 7.34 9.36 2.4 0 4.12-.82 5.47-2.47v-4.06c-1.06 1.58-2.35 2.95-4.54 2.95-3.19 0-4.13-3.44-4.13-5.38 0-3.42 1.76-4.94 4.1-4.94 1.78 0 3.26.71 4.63 2.93v-4.97Zm11.28 11.81h-4.36v-13.54h-4.25v17.3h8.61v-3.77Zm17.27 3.77-5.06-17.3h-6.1l-5.09 17.3h4.27l1.06-4.06h5.59l1.06 4.06h4.27Zm6.21-17.3H108v17.3h4.27v-17.3Zm22.1 0h-6.39l-2.45 9.73-.28 3.64h-.24l-.32-3.67-2.46-9.71h-6.39v17.3h4.15v-10.44c0-.38-.1-2.16-.17-3.07h.24l3.07 13.51h3.96l3.07-13.51h.24l-.19 3.07v10.44h4.15v-17.3Z" style="fill:',
            hasUnclaimedDistribution(tokenId) ?
                generateColorHex(color, ColorType.DARK) :
                generateColorHex(color, ColorType.LIGHT),
            '"/><rect height="345" rx="15" ry="15" style="fill:url(#i)" width="330" x="15" y="180"/><text text-anchor="middle" style="font-family:ui-monospace,Cascadia Mono,Menlo,Monaco,Segoe UI Mono,Roboto Mono,Oxygen Mono,Ubuntu Monospace,Source Code Pro,Droid Sans Mono,Fira Mono,Courier,monospace;fill:',
            generateColorHex(color, ColorType.PRIMARY),
            ';font-weight:500;" x="307.5" y="156">',
            tokenId.toString(),
            '</text></svg>'
        );
    }

    function generateProposalStatus(uint256 proposalId) private view returns (string memory) {
        (PartyGovernance.ProposalStatus status, ) = PartyGovernance(address(this)).getProposalStateInfo(proposalId);

        if (status == PartyGovernance.ProposalStatus.Voting) {
            return "Voting now";
        } else if (status == PartyGovernance.ProposalStatus.Passed) {
            return "Passing";
        } else if (status == PartyGovernance.ProposalStatus.Ready) {
            return "Executable";
        } else if (status == PartyGovernance.ProposalStatus.InProgress) {
            return "In progress";
        } else if (status == PartyGovernance.ProposalStatus.Complete) {
            return "Complete";
        } else if (status == PartyGovernance.ProposalStatus.Defeated) {
            return "Defeated";
        } else if (status == PartyGovernance.ProposalStatus.Cancelled) {
            return "Cancelled";
        } else {
            return "Invalid";
        }
    }

    function generateVotingPowerPercentage(uint256 tokenId) private view returns (string memory) {
        uint256 intrinsicVotingPowerPercentage = PartyGovernance(address(this)).getDistributionShareOf(tokenId);

        if (intrinsicVotingPowerPercentage < 0.01e18) { return "<0.01";
        } else {
            return string.concat(
                // Integer part
                (intrinsicVotingPowerPercentage / 1e18).toString(),
                ".",
                // Last 2 decimals
                (intrinsicVotingPowerPercentage / 1e16 % 1e2).toString()
            );
        }
    }

    function getLatestProposalStatuses() private view returns(string[4] memory latestProposalStatuses) {
        uint256 latestProposalId = lastProposalId;
        uint256 numOfProposalsToDisplay = latestProposalId < 4 ? latestProposalId : 4;
        for (uint256 i; i < numOfProposalsToDisplay; ++i) {
            uint256 proposalId = latestProposalId - i;
            latestProposalStatuses[i] = string.concat(
                '#',
                proposalId.toString(),
                ' - ',
                generateProposalStatus(proposalId)
            );
        }
    }

    function hasUnclaimedDistribution(uint256 tokenId) private view returns (bool) {
        TokenDistributor distributor = TokenDistributor(_GLOBALS.getAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR));
        ITokenDistributorParty party = ITokenDistributorParty(address(this));
        uint256 lastDistributionId = distributor.lastDistributionIdPerParty(party);
        for (uint256 distributionId = 1; distributionId <= lastDistributionId; ++distributionId) {
            if (!distributor.hasPartyTokenIdClaimed(party, tokenId, distributionId)) {
                return true;
            }
        }
        return false;
    }

    function calcAnimationVariables()
        private
        view
        returns (
            uint256 duration,
            uint256 steps,
            uint256 delay,
            uint256 translateX
        )
    {
        translateX = bytes(name).length * 30 + 300;
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
