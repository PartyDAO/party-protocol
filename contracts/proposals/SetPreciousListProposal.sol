// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../tokens/IERC721.sol";
import "../party/PartyGovernance.sol";
import "../utils/LibAddress.sol";
import "../utils/LibSafeERC721.sol";

// Implements proposal to set a new list of precious tokens for a party. Can be
// used to add new preciouses or remove old preciouses from a party's list if it
// no longer holds them.
contract SetPreciousListProposal is ProposalStorage {
    using LibAddress for address;
    using LibSafeERC721 for IERC721;

    // ABI-encoded `proposalData` passed into execute.
    struct SetPreciousListProposalData {
        IERC721[] newPreciousTokens;
        uint256[] newPreciousTokenIds;
    }

    error MissingPrecious(IERC721 token, uint256 tokenId);
    error PreciousNotReceived(IERC721 token, uint256 tokenId);

    event UpdatedPreciouses(
        IERC721[] oldPreciousTokens,
        uint256[] oldPreciousTokenIds,
        IERC721[] newPreciousTokens,
        uint256[] newPreciousTokenIds
    );

    function _executeSetPreciousList(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal returns (bytes memory nextProgressData) {
        // Decode the proposal data.
        SetPreciousListProposalData memory data = abi.decode(
            params.proposalData,
            (SetPreciousListProposalData)
        );
        // Check for missing preciouses between the old and new precious lists.
        // Only allow removing preciouses if the party now longer holds them.
        _checkNoMissingPreciouses(
            params.preciousTokens,
            params.preciousTokenIds,
            data.newPreciousTokens,
            data.newPreciousTokenIds
        );
        // Set the new preciouses.
        _setPreciousList(data.newPreciousTokens, data.newPreciousTokenIds);
        emit UpdatedPreciouses(
            params.preciousTokens,
            params.preciousTokenIds,
            data.newPreciousTokens,
            data.newPreciousTokenIds
        );
        // Nothing left to do.
        return "";
    }

    function _checkNoMissingPreciouses(
        IERC721[] memory oldPreciousTokens,
        uint256[] memory oldPreciousTokenIds,
        IERC721[] memory newPreciousTokens,
        uint256[] memory newPreciousTokenIds
    ) internal view {
        for (uint256 i; i < oldPreciousTokens.length; i++) {
            IERC721 oldPreciousToken = oldPreciousTokens[i];
            uint256 oldPreciousTokenId = oldPreciousTokenIds[i];

            bool found;
            for (uint256 j; j < newPreciousTokens.length; j++) {
                if (
                    oldPreciousToken == newPreciousTokens[j] &&
                    oldPreciousTokenId == newPreciousTokenIds[j]
                ) {
                    found = true;
                    break;
                }
            }

            // Revert if attempting to remove a precious the party still holds.
            if (
                !found &&
                oldPreciousToken.safeOwnerOf(oldPreciousTokenId) == address(this)
            ) {
                revert MissingPrecious(oldPreciousToken, oldPreciousTokenId);
            }
        }
    }
}
