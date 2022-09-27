// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

interface IERC721Renderer {
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function contractURI() external view returns (string memory);
}
