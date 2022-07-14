// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../utils/LibSafeCast.sol";
import "./IERC721Renderer.sol";
import "../globals/IGlobals.sol";
import "forge-std/console2.sol";

// TODO: rename this to be gov nft renderer
contract ERC721Renderer is IERC721Renderer {
    using LibSafeCast for uint256;

    struct TokenInfo {
        address owner;
        address operator;
        uint256 votingPower;
    }

    IGlobals private _GLOBALS;

    string public name;
    string public symbol;
    // Who can call mint()
    address public mintAuthority;
    // owner -> numTokensHeldyOwner
    mapping (address => uint256) public balanceOf;

    uint256 private _tokenCounter;
    // owner -> operator -> isApproved
    mapping (address => mapping (address => bool)) public isApprovedForAll;
    // tokenId -> TokenInfo
    mapping (uint256 => TokenInfo) private _tokens;

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        console2.log("RENDERING");
        console2.log(name);
        return string(abi.encodePacked("<SVG>",name, symbol,"</SVG>"));
    }
}