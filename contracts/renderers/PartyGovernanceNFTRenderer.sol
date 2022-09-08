// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../utils/LibSafeCast.sol";
import "../utils/vendor/Strings.sol";
import "../utils/vendor/Base64.sol";

import "./IERC721Renderer.sol";
import "../globals/IGlobals.sol";
import "../party/PartyGovernance.sol";

contract PartyGovernanceNFTRenderer is IERC721Renderer {
    using LibSafeCast for uint256;

    error InvalidTokenIdError();

    IGlobals immutable _GLOBALS;

    // The renderer is called via delegateCall, so we need to declare the storage layout.
    // Run `yarn layout` to generate the current layout.
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

    string constant baseStyle = 'base';

    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    function textLine(string memory text, uint256 xPos, uint256 yPos) internal pure returns (string memory) {
        string[3] memory parts;

        parts[0] = string(abi.encodePacked(
            '<text x="',
            Strings.toString(xPos),
            '" y="',
            Strings.toString(yPos),
            '" class="',
            // TODO: Parameterize
            baseStyle,
            '">'
        ));
        parts[1] = text;
        parts[2] = '</text>';

        return string(abi.encodePacked(
            parts[0],
            parts[1],
            parts[2]
        ));
    }

    function renderNFTName() internal view returns (string memory) {
        return string.concat(name, " Party");
    }

    function renderTokenName(uint256 tokenId) internal view returns (string memory) {
        return string(abi.encodePacked(
            name,
            " #",
            Strings.toString(tokenId)
        ));
    }

    function renderTokenId(uint256 tokenId) internal pure returns (string memory) {
        return string(abi.encodePacked('#', Strings.toString(tokenId)));
    }

    function renderVotingPowerAndDistributionShare(uint256 tokenId) internal view returns (string memory) {
        // TODO: Write decimal string library
        uint256 votingPower = votingPowerByTokenId[tokenId] * 1e2 / _governanceValues.totalVotingPower;

        return string(
            abi.encodePacked(
                'Voting power: ', Strings.toString(votingPowerByTokenId[tokenId]),
                ' (',
                Strings.toString(votingPower),
                '%)'
            )
        );
    }

    function renderOwnerAddress(uint256 tokenId) internal view returns (string memory) {
        address owner = _ownerOf[tokenId];

        return string(abi.encodePacked('Owner: ', Strings.toHexString(owner)));
    }

    function renderDelegateAddress(uint256 tokenId) internal view returns (string memory) {
        address owner = _ownerOf[tokenId];
        address delegatedAddress = delegationsByVoter[owner];

        return string(abi.encodePacked('Delegate: ', Strings.toHexString(delegatedAddress)));
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if(_ownerOf[tokenId] == address(0)) {
            revert InvalidTokenIdError();
        }

        string[8] memory svgParts;

        svgParts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>text { fill: white; font-family: -apple-system, BlinkMacSystemFont, sans-serif; } .base { font-size: 11px; } .detail {font-size: 10px;}</style><rect width="100%" height="100%" fill="black" />';

        svgParts[1] = textLine(name, 10, 20);
        svgParts[3] = textLine(renderTokenId(tokenId), 300, 20);

        svgParts[2] = textLine(symbol, 10, 60);

        svgParts[4] = textLine(renderVotingPowerAndDistributionShare(tokenId), 10, 80);

        svgParts[5] = textLine(renderOwnerAddress(tokenId), 10, 120);
        svgParts[6] = textLine(renderDelegateAddress(tokenId), 10, 140);

        svgParts[7] = '</svg>';

        string memory output = string(
            abi.encodePacked(
                svgParts[0], svgParts[1], svgParts[2],
                svgParts[3], svgParts[4], svgParts[5],
                svgParts[6], svgParts[7]
            )
        );

        string memory json = Base64.encode(bytes(
            string(
                abi.encodePacked(
                    '{"name":"',
                    renderTokenName(tokenId),
                    '", "description": "AuctionCrowdfund Governance NFT", "image": "data:image/svg+xml;base64,',
                    Base64.encode(bytes(output)),
                    '"}'
                )
            )
        ));

        output = string(abi.encodePacked('data:application/json;base64,', json));

        return output;
    }

    function contractURI() external view returns (string memory) {
        string memory json = Base64.encode(bytes(
            string(
                abi.encodePacked(
                    '{"name":"',
                    renderNFTName(),
                    '", "description":"',
                    "AuctionCrowdfund Governance NFTs give you voting power in a AuctionCrowdfund party.",
                    '"}'
                    // '", "image": "data:image/svg+xml;base64,',
                    // Base64.encode(bytes(output)),
                    // '"}'
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
}
