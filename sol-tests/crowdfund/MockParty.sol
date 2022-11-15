// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "contracts/tokens/IERC721Receiver.sol";
import "contracts/vendor/solmate/ERC721.sol";

contract MockParty is ERC721("MockParty", "MOCK") {
    event MockMint(address caller, address owner, uint256 amount, address delegate);

    uint256 public tokenCount;

    function tokenURI(uint256 id) public view override returns (string memory) {}

    function mint(
        address owner,
        uint256 amount,
        address delegate
    ) external returns (uint256 tokenId) {
        tokenId = ++tokenCount;
        _safeMint(owner, tokenId);
        emit MockMint(msg.sender, owner, amount, delegate);
    }
}
