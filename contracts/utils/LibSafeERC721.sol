// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../tokens/IERC721.sol";
import "./LibRawResult.sol";

library LibSafeERC721 {
    using LibRawResult for bytes;

    // Call IERC721.ownerOf() without reverting if the ID does not exist.
    function safeOwnerOf(IERC721 token, uint256 tokenId)
        internal
        view
        returns (address owner)
    {
        try token.ownerOf(tokenId) returns (address owner_) {
            return owner_;
        } catch {
            return address(0);
        }
    }
}
