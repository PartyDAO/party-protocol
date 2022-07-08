// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "solmate/tokens/ERC1155.sol";
import "../contracts/tokens/IERC1155.sol";

contract DummyERC1155 is IERC1155, ERC1155 {
    function deal(address owner, uint256 tokenId, uint256 amount) external {
        _mint(owner, tokenId, amount, "");
    }
}
