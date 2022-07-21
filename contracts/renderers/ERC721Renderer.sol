// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../utils/LibSafeCast.sol";
import "../utils/Base64.sol";

import "./IERC721Renderer.sol";
import "../globals/IGlobals.sol";
import "../party/PartyGovernance.sol";
import "forge-std/console2.sol";

// TODO: Reconcile this with deploy.sol copy and paste. Should we switch to the npm module?
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

    /**
     * @dev Converts an `address` with fixed length of 20 bytes to its not checksummed ASCII `string` hexadecimal representation.
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), _ADDRESS_LENGTH);
    }
}

// TODO: rename this to be gov nft renderer
contract ERC721Renderer is IERC721Renderer {
    using LibSafeCast for uint256;

    IGlobals immutable _GLOBALS;

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
    string constant detailStyle = 'detail';

    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    function renderTokenId(uint256 tokenId) internal view returns (string memory) {
        return string(abi.encodePacked('#', Strings.toString(tokenId)));
    }

    function renderVotingPowerAndDistributionShare(uint256 tokenId) internal view returns (string memory) {
        // TODO: require that votingPowerByTokenId[tokenId] exists?

        // TODO: Write decimal string printing
        uint256 votingPower = votingPowerByTokenId[tokenId]  / _governanceValues.totalVotingPower;

        console2.log(votingPowerByTokenId[tokenId]);
        console2.log(_governanceValues.totalVotingPower);
        console2.log(votingPower);

        return string(
            abi.encodePacked(
                'Voting power: ', Strings.toString(votingPowerByTokenId[tokenId]),
                ' (',
                Strings.toString(votingPower),
                '%)'
            )
        );
    }

    function renderTextLine(string memory text, uint256 xPos, uint256 yPos) internal view returns (string memory) {
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
        parts[2] = renderTextLine(renderTokenId(tokenId), 300, 20);

        parts[3] = renderTextLine(renderVotingPowerAndDistributionShare(tokenId), 10, 60);

        parts[5] = renderTextLine(renderOwnerAddress(tokenId), 10, 100);
        parts[6] = renderTextLine(renderDelegateAddress(tokenId), 10, 120);

        parts[7] = '</svg>';

        string memory output = string(
            abi.encodePacked(
                parts[0], parts[1], parts[2],
                parts[3], parts[4], parts[5],
                parts[6], parts[7]
            )
        );

        string memory json = Base64.encode(bytes(
            string(
                abi.encodePacked(
                    '{"name": "Bag #',
                    Strings.toString(tokenId),
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