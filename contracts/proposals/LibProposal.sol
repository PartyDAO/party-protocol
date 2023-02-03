// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../tokens/IERC721.sol";

library LibProposal {
    uint256 internal constant PROPOSAL_FLAG_UNANIMOUS = 0x1;

    function isTokenPrecious(
        address token,
        address[] memory preciousTokens
    ) internal pure returns (bool) {
        for (uint256 i; i < preciousTokens.length; ++i) {
            if (token == preciousTokens[i]) {
                return true;
            }
        }
        return false;
    }

    function isTokenIdPrecious(
        address token,
        uint256 tokenId,
        address[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) internal pure returns (bool) {
        for (uint256 i; i < preciousTokens.length; ++i) {
            if (token == preciousTokens[i] && tokenId == preciousTokenIds[i]) {
                return true;
            }
        }
        return false;
    }
}
