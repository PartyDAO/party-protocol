// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Compatibility helpers for ERC20s.
Library LibERC20Compat {
    function compatTransfer(IERC20 token, address to, uint256 tokenId)
        internal
    {
        // call transfer() while handling all implementation quirks
    }
}
