// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// NFT functionality for PartyBid/Buy contributions.
// This NFT is read-only.
contract PartyCrowdfundNFT is IERC721 {
    address private immutable GLOBALS;

    mapping (uint256 => address) ownerOf;
    string public name;
    string public symbol;

    constructor(IGlobals globals) {
        GLOBALS = globals;
    }

    modifier alwaysRevert() {
        revert('ALWAYS FAILING');
    }

    function transferFrom(address owner, address to, uint256 tokenId)
        external
        alwaysRevert
    {}

    function safeTransferFrom(address owner, address to, uint256 tokenId, bytes memory data)
        external
        alwaysRevert
    {}

    function approve(address spender, uint256 tokenId)
        external
        alwaysRevert
    {}

    function setApprovalForAll(address spender, bool approved)
        external
        alwaysRevert
    {}

    function tokenURI(uint256 tokenId) external external /* view */ returns (string)
    {
        (GLOBALS.getAddress(PARTY_CF_NFT_RENDER_IMPL)).delegatecall(msg.data);
    }

    function _mint(address owner) internal returns (uint256 tokenId)
    {
        tokenId = uint256(uint160(owner));
        if (ownerOf[tokenId] != owner) {
            ownerOf[tokenId] = owner;
            emit Transfer(address(0), owner, tokenId);
        }
    }

    function _burn(address owner) internal {
        uint256 tokenId = uint256(uint160(owner));
        if (ownerOf[tokenId] == owner) {
            ownerOf[tokenId] = address(0);
            emit Transfer(owner, address(0), tokenId);
        }
    }

    function _initialize(string name_, string symbol_) internal {
        name = name_;
        symbol = symbol_;
    }

    // ...
}