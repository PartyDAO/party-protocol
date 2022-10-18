// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.17;

import "../utils/LibSafeCast.sol";
import "../utils/vendor/Strings.sol";
import "../utils/vendor/Base64.sol";

import "./IERC721Renderer.sol";
import "../globals/IGlobals.sol";
import "../party/PartyGovernance.sol";
import "../party/PartyGovernanceNFT.sol";
import "../distribution/TokenDistributor.sol";
import "./RendererStorage.sol";
import "./fonts/IFont.sol";

contract PartyNFTRenderer is IERC721Renderer {
    using LibSafeCast for uint256;
    using Strings for uint256;
    using Strings for address;

    error InvalidTokenIdError();

    struct ProposalData {
        uint256 id;
        string status;
    }

    uint256 constant PARTY_CARD_DATA_1 = 2;
    uint256 constant PARTY_CARD_DATA_2 = 3;
    uint256 constant PARTY_CARD_DATA_3 = 4;
    uint256 constant PARTY_CARD_DATA_4 = 5;

    IGlobals immutable _GLOBALS;
    RendererStorage immutable _storage;
    IFont immutable _font;

    constructor(IGlobals globals, RendererStorage rendererStorage, IFont font) {
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

        string memory partyName = name;
        string memory externalURL = generateExternalURL();
        string memory votingPower = generateVotingPowerPercentage(tokenId);
        string[4] memory latestProposalStatuses = getLatestProposalStatuses();
        bool hasUnclaimed = hasUnclaimedDistribution(tokenId);

        return string.concat(
            'data:application/json;base64,',
            Base64.encode(abi.encodePacked(
                '{"name":"',
                generateName(partyName, tokenId),
                '", "description":"',
                generateDescription(partyName, votingPower, externalURL, tokenId),
                '", "external_url":"',
                externalURL,
                '", "attributes": [',
                generateAttributes(votingPower),
                '], "image": "data:image/svg+xml;base64,',
                Base64.encode(abi.encodePacked(
                    // Split to avoid stack too deep errors
                    generateSVG1(partyName),
                    generateSVG2(tokenId, partyName, hasUnclaimed),
                    generateSVG3(latestProposalStatuses, votingPower),
                    generateSVG4()
                )),
                '"}'
            ))
        );
    }

    function generateName(string memory partyName, uint256 tokenId) private pure returns (string memory) {
        return string.concat(partyName, ' Card #', tokenId.toString());
    }

    function generateExternalURL() private view returns (string memory) {
        return string.concat('https://partybid.app/party/', address(this).toHexString());
    }

    function generateDescription(
        string memory partyName,
        string memory votingPower,
        string memory externalURL,
        uint256 tokenId
    ) private pure returns (string memory) {
        return string.concat(
            'Card #',
            tokenId.toString(),
            ' in ',
            partyName,
            ". This item represents ",
            votingPower,
            '% membership in the party. Head to ',
            externalURL,
            " to view the party's latest activity."
        );
    }

    function generateAttributes(string memory votingPower) private pure returns (string memory) {
        return string.concat(
            '{"trait_type":"Voting Power", "value":',
            votingPower,
            ', "max_value":100}'
        );
    }

    function generateSVG1(string memory partyName) private view returns (string memory) {
        (uint256 duration, uint256 steps, uint256 delay, uint256 translateX) = calcAnimationVariables(partyName);
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="362" height="542" fill="none"><style>.A{animation:move ',
            duration.toString(),
            's steps(',
            steps.toString(),
            ') infinite;}.C{fill:#91a6c3}.D{fill:#50586d}.E{font-family:Console}.F{font-size:48px}.G{fill:#a7b8cf}.H{stroke-miterlimit:10}.I{animation-delay:',
            delay.toString(),
            's}@keyframes move{to{transform:translateX(-',
            translateX.toString(),
            'px)}}@font-face{font-family:&quot;Console&quot;;src:url(',
            _font.getFont(),
            ');}</style>',
            _storage.readFile(PARTY_CARD_DATA_1)
        );
    }

    function generateSVG2(
        uint256 tokenId,
        string memory partyName,
        bool hasUnclaimed
    ) private view returns (string memory) {
        return string.concat(
            tokenId.toString(),
            '</tspan></text><path d="M331 181H31c-8.284 0-15 6.716-15 15v315c0 8.284 6.716 15 15 15h300c8.284 0 15-6.716 15-15V196c0-8.284-6.716-15-15-15z" class="G"/><path d="M331 181a15.01 15.01 0 0 1 15 15v315a15.01 15.01 0 0 1-15 15H31a15.01 15.01 0 0 1-15-15V196a15.01 15.01 0 0 1 15-15h300zm0-1H31c-8.82 0-16 7.18-16 16v315c0 8.82 7.18 16 16 16h300c8.82 0 16-7.18 16-16V196c0-8.82-7.18-16-16-16z" fill="url(#J)"/><path d="M321 469C324.86 469 328 472.14 328 476V501C328 504.86 324.86 508 321 508H198.5C194.64 508 191.5 504.86 191.5 501V476C191.5 472.14 194.64 469 198.5 469H321ZM321 466H198.5C192.98 466 188.5 470.48 188.5 476V501C188.5 506.52 192.98 511 198.5 511H321C326.52 511 331 506.52 331 501V476C331 470.48 326.52 466 321 466Z" fill="#50586D"/><path d="M31 476L31 501C31 506.523 35.4772 511 41 511H163.5C169.023 511 173.5 506.523 173.5 501V476C173.5 470.477 169.023 466 163.5 466H41C35.4772 466 31 470.477 31 476Z" fill="',
            hasUnclaimed ? '#50586D' : '#91A6C3',
            _storage.readFile(PARTY_CARD_DATA_2),
            partyName,
            '</tspan></text><text class="A D E F I"><tspan x="328" y="241.984">',
            partyName,
            '</tspan></text></g>'
        );
    }

    function generateSVG3(string[4] memory latestProposalStatuses, string memory votingPower)
        private
        pure
        returns (string memory)
    {
        return string.concat(
            '<clipPath id="B"><path d="M31 281h300v27H31z" class="C"/></clipPath><g clip-path="url(#B)"><path d="M31 281h300v27H31z" class="C"/><text class="D E F"><tspan x="31" y="301.984">',
            latestProposalStatuses[0],
            '</tspan></text></g><clipPath id="C"><path d="M31 311h300v27H31z" class="C"/></clipPath><g clip-path="url(#C)"><path d="M31 311h300v27H31z" class="C"/><text class="D E F"><tspan x="31" y="331.984">',
            latestProposalStatuses[1],
            '</tspan></text></g><clipPath id="D"><path d="M31 341h300v27H31z" class="C"/></clipPath><g clip-path="url(#D)"><path d="M31 341h300v27H31z" class="C"/><text class="D E F"><tspan x="31" y="361.984">',
            latestProposalStatuses[2],
            '</tspan></text></g><clipPath id="E"><path d="M31 371h300v27H31z" class="C"/></clipPath><g clip-path="url(#E)"><path d="M31 371h300v27H31z" class="C"/><text class="D E F"><tspan x="31" y="391.984">',
            latestProposalStatuses[3],
            '</tspan></text></g><path d="M199 475h123v27H199z" class="C"/><text class="D E F"><tspan x="202" y="495.984">',
            votingPower,
            '%</tspan></text>'
        );
    }

    function generateSVG4() private view returns (string memory) {
        return string.concat(
            _storage.readFile(PARTY_CARD_DATA_3),
            _storage.readFile(PARTY_CARD_DATA_4)
        );
    }

    function generateProposalStatus(uint256 proposalId) private view returns (string memory) {
        (PartyGovernance.ProposalStatus status, ) = PartyGovernance(address(this)).getProposalStateInfo(proposalId);

        if (status == PartyGovernance.ProposalStatus.Voting) {
            return "Voting";
        } else if (status == PartyGovernance.ProposalStatus.Passed) {
            return "Passing";
        } else if (status == PartyGovernance.ProposalStatus.Ready) {
            return "Ready";
        } else if (status == PartyGovernance.ProposalStatus.InProgress) {
            return "In Progress";
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
        return toDecimalString(intrinsicVotingPowerPercentage);
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

    function calcAnimationVariables(string memory partyName)
        private
        pure
        returns (
            uint256 duration,
            uint256 steps,
            uint256 delay,
            uint256 translateX
        )
    {
        translateX = bytes(partyName).length * 30 + 300;
        duration = translateX / 56;
        if (duration % 2 != 0) {
            // Make duration even so that the animation delay is always exactly
            // half of the duration
            duration += 1;
        }
        delay = duration / 2;
        steps = translateX / 6;
    }

    // Convert 18 decimals number to stringified 2 decimal number
    function toDecimalString(uint256 value) private pure returns (string memory) {
        if (value < 0.01e18) {
            return "<0.01";
        } else {
            return string.concat(
                // Integer part
                (value / 1e18).toString(),
                ".",
                // Last 2 decimals
                (value / 1e16 % 1e2).toString()
            );
        }
    }
}
