// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../contracts/vendor/solmate/ERC1155.sol";

contract DummyERC1155 is ERC1155 {
    function uri(uint256 id) public view override returns (string memory) {}

    function deal(address owner, uint256 tokenId, uint256 amount) public {
        _mint(owner, tokenId, amount, "");
    }
}
