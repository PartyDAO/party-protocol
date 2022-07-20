// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../utils/LibSafeCast.sol";
import "./IERC721Renderer.sol";
import "../globals/IGlobals.sol";
import "../party/PartyGovernance.sol";
import "forge-std/console2.sol";

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


    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }
 
    function tokenURI(uint256 tokenId) external view returns (string memory) {
       return string(abi.encodePacked("<SVG>",name,symbol,"</SVG>"));
    }
}