// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// NFT functionality for PartyBid/Buy contributions.
// This NFT is soulbound and read-only.
contract PartyCrowdfundNFT is IERC721, ReadOnlyDelegateCall {

    error AlreadyBurnedError(address owner, uint256 tokenId);
    error InvalidTokenError(uint256 tokenId);

    address private immutable   _GLOBALS;

    string public name;
    string public symbol;

    mapping (uint256 => address) private _owners;

    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    // Must be called once by freshly deployed PartyProxy instances.
    function initialize(string name, string symbol)
        public
        virtual
    {
        name = name_;
        symbol = symbol_;
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

    function tokenURI(uint256 tokenId) external /* view */ returns (string)
    {
        _readOnlyDelegateCall(
            // An instance of IERC721Renderer
            _GLOBALS.getAddress(LibGobals.GLOBAL_CF_NFT_RENDER_IMPL)
        );
    }

    function ownerOf(uint256 tokenId) external view returns (address owner) {
        owner = _owners[tokenId];
        if (owner == address(0)) {
            revert InvalidTokenError(tokenId);
        }
    }

    function _doesTokenExistFor(address owner) internal view returns (bool) {
        return _owners[uint256(uint160(tokenId))] != address(0);
    }

    function _mint(address owner) internal returns (uint256 tokenId)
    {
        tokenId = uint256(uint160(owner));
        if (_owners[tokenId] != owner) {
            _owners[tokenId] = owner;
            emit Transfer(address(0), owner, tokenId);
        }
    }

    function _burn(address owner) internal {
        uint256 tokenId = uint256(uint160(owner));
        if (_owners[tokenId] == owner) {
            _owners[tokenId] = address(0);
            emit Transfer(owner, address(0), tokenId);
            return;
        }
        revert AlreadyBurnedError(owner, tokenId);
    }
}
