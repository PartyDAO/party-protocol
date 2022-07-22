// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../utils/LibSafeCast.sol";
import "../utils/Strings.sol";
import "../utils/Base64.sol";

import "./IERC721Renderer.sol";
import "../globals/IGlobals.sol";
import "../party/PartyGovernance.sol";
import "forge-std/console2.sol";

contract PartyGovernanceNFTRenderer is IERC721Renderer {
    using LibSafeCast for uint256;

    IGlobals immutable _GLOBALS;

    // The renderer is called via delegateCall, so we need to declare the storage layout.
    // Run `yarn layout` to see generate the current layout.
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

    function tokenName(uint256 tokenId) internal view returns (string memory) {
        return string(abi.encodePacked(
            name,
            " #",
            Strings.toString(tokenId)
        ));
    }

    function renderTextLine(string memory text, uint256 xPos, uint256 yPos) internal pure returns (string memory) {
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

    function renderTokenId(uint256 tokenId) internal pure returns (string memory) {
        return string(abi.encodePacked('#', Strings.toString(tokenId)));
    }

    function renderVotingPowerAndDistributionShare(uint256 tokenId) internal view returns (string memory) {
        // TODO: require that votingPowerByTokenId[tokenId] exists?

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
        // TODO: require?
        address owner = _ownerOf[tokenId];

        return string(abi.encodePacked('Owner: ', Strings.toHexString(owner)));
    }

    function renderDelegateAddress(uint256 tokenId) internal view returns (string memory) {
        // TODO: require?
        address owner = _ownerOf[tokenId];
        address delegatedAddress = delegationsByVoter[owner];

        return string(abi.encodePacked('Delegate: ', Strings.toHexString(delegatedAddress)));
    }
 
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        // TODO: Require votingPowerByTokenId to exist for tokenId?

        string[17] memory parts;

        parts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>text { fill: white; font-family: -apple-system, BlinkMacSystemFont, sans-serif; } .base { font-size: 11px; } .detail {font-size: 10px;}</style><rect width="100%" height="100%" fill="black" />';

        parts[1] = renderTextLine(name, 10, 20);
        parts[3] = renderTextLine(renderTokenId(tokenId), 300, 20);

        parts[2] = renderTextLine(symbol, 10, 60);

        parts[4] = renderTextLine(renderVotingPowerAndDistributionShare(tokenId), 10, 80);

        parts[5] = renderTextLine(renderOwnerAddress(tokenId), 10, 120);
        parts[6] = renderTextLine(renderDelegateAddress(tokenId), 10, 140);

        parts[7] = '</svg>';

        string memory output = string(
            abi.encodePacked(
                parts[0], parts[1], parts[2],
                parts[3], parts[4], parts[5],
                parts[6], parts[7], parts[8]
            )
        );

        string memory json = Base64.encode(bytes(
            string(
                abi.encodePacked(
                    '{"name":"',
                    tokenName(tokenId),
                    '", "description": "PartyBid Governance NFT", "image": "data:image/svg+xml;base64,',
                    Base64.encode(bytes(output)),
                    '"}'
                )
            )
        ));

        output = string(abi.encodePacked('data:application/json;base64,', json));

        return output;
    }
}