// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { IERC721 } from "../tokens/IERC721.sol";
import { IERC1155 } from "../tokens/IERC1155.sol";
import { IEIP165 } from "./IEIP165.sol";

library LibSafeNFT {

    /// changed: param type for `token` into address from IERC721
    /// changed: made d lowercase in ``tokenID` does not exist.` and removed period

    // Call `IERC721.ownerOf()` else `ERC1155.balanceOf()` without reverting and return `address(0)` if:
    // - `tokenId` does not exist
    // — `tokenId` does not belong to address(this) for ERC1155
    // - `token` is an EOA
    // - `token` is an empty contract
    // - `token` is a "bad" implementation of ERC721 that returns nothing for
    //   `ownerOf()`
    // - `token` is a "bad" implementation of ERC1155 that returns nothing for
    //   `balanceOf()`
    function safeOwnerOf(address token, uint256 tokenId) internal view returns (address owner) {
        bool s;
        bytes memory r;

        // note: to account for tokens that don't implement EIP-165, it seems optimal to 
        //       simply attempt the call — as opposed to calling supportsInterface

        (s, r) = token.staticcall(
            abi.encodeCall(IERC721.ownerOf, (tokenId))
        );

        if (!s || r.length < 32) {
            (s, r) = token.staticcall(
                abi.encodeCall(IERC1155.balanceOf, (address(this), tokenId))
            );

            if (!s || r.length < 32 || abi.decode(r,(uint256)) == 0) {
                return address(0);
            } 

            return address(this);
        }

        return abi.decode(r, (address));
    }
    
    /// review: would like some feedback 
    /// @notice returns true if token is ERC1155
    function isERC1155(address token) internal view returns (bool) {
        (
            bool s, 
            bytes memory r
        ) = token.staticcall(abi.encodeCall(IEIP165.supportsInterface,(type(IERC1155).interfaceId)));

        // review: how should we handle a token that doesn't expose .supportsInterface?
        //         the assumption here is, if it don't expose that function, it's likely a bad ERC721
        return !s ? s : abi.decode(r,(bool));
    }
}