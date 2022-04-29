// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

interface IERC721Renderer {
    function tokenURI(uint256 tokenId) external external view returns (string);
}
