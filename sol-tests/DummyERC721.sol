// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../contracts/tokens/IERC721.sol";
import "../contracts/tokens/IERC721Receiver.sol";

contract DummyERC721 is IERC721 {
    string public constant name = "DummyERC721";
    string public constant symbol = "DUMDUM";
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) private _ownerOf;
    uint256 private _lastId;

    modifier onlyOwnedBy(uint256 tokenId, address owner) {
        require(_ownerOf[tokenId] == owner, "DummyERC721/NOT_OWNED");
        _;
    }

    modifier onlyOwnedByOrIsApprovedForAll(uint256 tokenId, address whom) {
        address owner = _ownerOf[tokenId];
        require(owner != address(0), "DummyERC721/INVALID_TOKEN");
        if (owner != whom) {
            require(isApprovedForAll[owner][whom], "DummyERC721/NOT_APPROVED");
        }
        _;
    }

    function ownerOf(uint256 tokenId) external view returns (address owner) {
        owner = _ownerOf[tokenId];
        require(owner != address(0), "INVALID_TOKEN");
        return owner;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        if (interfaceId == 0x01ffc9a7) {
            return true;
        }
        if (interfaceId == 0x80ac58cd) {
            return true;
        }
        if (interfaceId == 0xffffffff) {
            return false;
        }
        return false;
    }

    function mint(address owner) external payable returns (uint256 id) {
        id = ++_lastId;
        _ownerOf[id] = owner;
        ++balanceOf[owner];
        emit Transfer(address(0), owner, id);
    }

    function approve(
        address operator,
        uint256 tokenId
    ) external onlyOwnedByOrIsApprovedForAll(tokenId, msg.sender) {
        getApproved[tokenId] = operator;
        emit Approval(msg.sender, operator, tokenId);
    }

    function setApprovalForAll(address operator, bool isApproved) external {
        isApprovedForAll[msg.sender][operator] = isApproved;
        emit ApprovalForAll(msg.sender, operator, isApproved);
    }

    function transferFrom(address owner, address to, uint256 tokenId) external {
        _transferFrom(owner, to, tokenId);
    }

    function safeTransferFrom(address owner, address to, uint256 tokenId) external {
        safeTransferFrom(owner, to, tokenId, "");
    }

    function safeTransferFrom(
        address owner,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public {
        _transferFrom(owner, to, tokenId);
        uint256 toCodeSize;
        assembly {
            toCodeSize := extcodesize(to)
        }
        if (toCodeSize != 0) {
            bytes4 r = IERC721Receiver(to).onERC721Received(msg.sender, owner, tokenId, data);
            require(r == IERC721Receiver.onERC721Received.selector, "DummyERC721/RECEIVE_FAILED");
        }
    }

    function _transferFrom(
        address owner,
        address to,
        uint256 tokenId
    ) private onlyOwnedBy(tokenId, owner) {
        require(to != address(0), "DummyERC721/BAD_TRANSFER");
        if (owner != msg.sender) {
            if (!isApprovedForAll[owner][msg.sender]) {
                require(getApproved[tokenId] == msg.sender, "DummyERC721/NOT_APPROVED");
            }
        }
        getApproved[tokenId] = address(0);
        _ownerOf[tokenId] = to;
        --balanceOf[owner];
        ++balanceOf[to];
        emit Transfer(owner, to, tokenId);
    }
}
