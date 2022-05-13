// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../tokens/IERC721.sol";
import "../utils/ReadOnlyDelegateCall.sol";
import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";

// NFT functionality for PartyBid/Buy contributions.
// This NFT is soulbound and read-only.
contract PartyCrowdfundNFT is IERC721, ReadOnlyDelegateCall {

    error AlreadyBurnedError(address owner, uint256 tokenId);
    error InvalidTokenError(uint256 tokenId);

    IGlobals private immutable _GLOBALS;

    string public name;
    string public symbol;

    mapping (uint256 => address) private _owners;

    modifier alwaysRevert() {
        revert('ALWAYS FAILING');
        _; // Compiler requires this.
    }

    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    // Must be called once by freshly deployed PartyProxy instances.
    function initialize(string memory name_, string memory symbol_)
        internal
        virtual
    {
        name = name_;
        symbol = symbol_;
    }

    function transferFrom(address owner, address to, uint256 tokenId)
        external
        alwaysRevert
    {}

    function safeTransferFrom(address owner, address to, uint256 tokenId, bytes calldata data)
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

    function getApproved(uint256 tokenId)
        external
        pure
        returns (address)
    {
        return address(0);
    }

    function isApprovedForAll(address owner, address operator)
        external
        pure
        returns (bool)
    {
        return false;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        if (interfaceId == 0x01ffc9a7) {
            return true;
        }
        if (interfaceId == 0xffffffff) {
            return false;
        }
        return interfaceId == 0x5b5e139f; // ERC721Metadata
    }

    function tokenURI(uint256 tokenId) external /* view */ returns (string memory)
    {
        _readOnlyDelegateCall(
            // An instance of IERC721Renderer
            _GLOBALS.getAddress(LibGlobals.GLOBAL_CF_NFT_RENDER_IMPL),
            msg.data
        );
    }

    function ownerOf(uint256 tokenId) external view returns (address owner) {
        owner = _owners[tokenId];
        if (owner == address(0)) {
            revert InvalidTokenError(tokenId);
        }
    }

    function balanceOf(address owner) external view returns (uint256 numTokens) {
        return _doesTokenExistFor(owner) ? 1 : 0;
    }

    function _doesTokenExistFor(address owner) internal view returns (bool) {
        return _owners[uint256(uint160(owner))] != address(0);
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
