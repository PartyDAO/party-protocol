// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import "./IERC721Renderer.sol";

contract DummyERC721Renderer is IERC721Renderer {
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        return string(abi.encode(address(this), tokenId));
    }

    function contractURI() external pure returns (string memory) {
        return "";
    }
}
