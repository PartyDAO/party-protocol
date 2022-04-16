// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Upgradeable proposals logic contract interface.
interface IPartyProposals {
    function isValidProposal(IERC721 erc721Token, uint256 tokenId, bytes memory proposal) external view returns (bool);
    function executeProposal(IERC721 erc721Token, uint256 tokenId, bytes memory proposal) external returns (bool);
}