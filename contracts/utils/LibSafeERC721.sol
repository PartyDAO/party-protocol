// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../tokens/IERC721.sol";
import "./LibRawResult.sol";

library LibSafeERC721 {
    using LibRawResult for bytes;

    // Call `IERC721.ownerOf()` without reverting and return `address(0)` if:
    // - `tokenID` does not exist.
    // - `token` is an EOA
    // - `token` is an empty contract
    // - `token` is a "bad" implementation of ERC721 that returns nothing for
    //   `ownerOf()`
    function safeOwnerOf(IERC721 token, uint256 tokenId) internal view returns (address owner) {
        (bool s, bytes memory r) = address(token).staticcall(
            abi.encodeCall(token.ownerOf, (tokenId))
        );

        if (!s || r.length < 32) {
            return address(0);
        }

        return abi.decode(r, (address));
    }
}
