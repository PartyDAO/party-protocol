// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../DummyERC721.sol";

contract TestERC721Vault {
    DummyERC721 public token = new DummyERC721();

    function mint() external returns (uint256 tokenId) {
        return token.mint(address(this));
    }

    function claim(uint256 tokenId) external payable {
        token.safeTransferFrom(address(this), msg.sender, tokenId, "");
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
