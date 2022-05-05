// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

contract DummyERC721Renderer is IERC721Renderer {
    function tokenURI(uint256 tokenId) external view returns (string) {
        // TODO: make this human readable
        return string(abi.encode(address(this), tokenId));
    }
}
