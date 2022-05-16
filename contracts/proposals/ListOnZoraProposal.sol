// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC721.sol";
import "../utils/LibRawResult.sol";

import "./zora/IZoraAuctionHouse.sol";
import "./IProposalExecutionEngine.sol";

// Implements arbitrary call proposals.
contract ListOnZoraProposal {
    using LibRawResult for bytes;

    enum ZoraStep {
        None,
        ListedOnZora
    }

    // ABI-encoded `proposalData` passed into execute.
    struct ZoraProposalData {
        uint256 listPrice;
        uint40 duration;
    }

    // ABI-encoded `progressData` passed into execute in the `ListedOnZora` step.
    struct ZoraProgressData {
        // Acution ID.
        uint256 auctionId;
        // Expiration timestamp of the auction, if no one bids.
        uint40 minExpiry;
    }

    error ZoraListingNotExpired(uint256 auctionId, uint40 expiry);

    // keccak256(abi.encodeWithSignature('Error(string)', "Auction hasn't begun"))
    bytes32 constant internal AUCTION_HASNT_BEGUN_ERROR_HASH =
        0x54a53788b7942d79bb6fcd40012c5e867208839fa1607e1f245558ee354e9565;
    // keccak256(abi.encodeWithSignature('Error(string)', "Auction doesn't exit"))
    bytes32 constant internal AUCTION_DOESNT_EXIST_ERROR_HASH =
        0x474ba0184a7cd5de777156a56f3859150719340a6974b6ee50f05c58139f4dc2;
    IZoraAuctionHouse public immutable ZORA;

    constructor(IZoraAuctionHouse zoraAuctionHouse) {
        ZORA = zoraAuctionHouse;
    }

    // Try to create a listing (ultimately) on OpenSea.
    // Creates a listing on Zora AH for list price first. When that ends,
    // calling this function again will list in on OpenSea. When that ends,
    // calling this function again will cancel the listing.
    function _executeListOnZora(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    )
        internal
        returns (bytes memory nextProgressData)
    {
        (ZoraProposalData memory data) = abi.decode(params.proposalData, (ZoraProposalData));
        ZoraStep step = params.progressData.length == 0
            ? ZoraStep.None
            : abi.decode(params.progressData, (ZoraStep));
        if (step == ZoraStep.None) {
            // Proposal hasn't executed yet.
            (uint256 auctionId, uint40 minExpiry) = _createZoraAuction(
                data.listPrice,
                data.duration,
                params.preciousToken,
                params.preciousTokenId
            );
            return abi.encode(ZoraStep.ListedOnZora, ZoraProgressData({
                auctionId: auctionId,
                minExpiry: minExpiry
            }));
        }
        assert(step == ZoraStep.ListedOnZora);
        (, ZoraProgressData memory pd) =
            abi.decode(params.progressData, (ZoraStep, ZoraProgressData));
        if (pd.minExpiry < uint40(block.timestamp)) {
            revert ZoraListingNotExpired(pd.auctionId, pd.minExpiry);
        }
        _settleZoraAuction(pd.auctionId, params.preciousToken, params.preciousTokenId);
        // Nothing left to do.
        return "";
    }

    function _createZoraAuction(
        uint256 listPrice,
        uint256 duration,
        IERC721 token,
        uint256 tokenId
    )
        internal
        returns (uint256 auctionId, uint40 minExpiry)
    {
        minExpiry = uint40(block.timestamp) + uint40(duration);
        token.approve(address(ZORA), tokenId);
        auctionId = ZORA.createAuction(
            tokenId,
            token,
            duration,
            listPrice,
            payable(address(0)),
            0,
            IERC20(address(0)) // Indicates ETH sale
        );
    }


    function _settleZoraAuction(uint256 auctionId, IERC721 token, uint256 tokenId)
        internal
        returns (bool sold)
    {
        // Getting the state of an auction is super expensive so it seems
        // cheaper to just let `endAuction` fail and react to the error.
        try ZORA.endAuction(auctionId) {
        } catch (bytes memory errData) {
            bytes32 errHash = keccak256(errData);
            if (errHash == AUCTION_HASNT_BEGUN_ERROR_HASH) {
                // No bids placed. Just cancel it.
                ZORA.cancelAuction(auctionId);
                return false;
            } else if (errHash != AUCTION_DOESNT_EXIST_ERROR_HASH) {
                errData.rawRevert();
            }
            // Already settled by someone else. Nothing to do.
        }
        return token.ownerOf(tokenId) != address(this);
    }
}
