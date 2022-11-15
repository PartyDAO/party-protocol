// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC721.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibSafeERC721.sol";
import "../utils/LibSafeCast.sol";

import "../vendor/markets/IZoraAuctionHouse.sol";
import "./IProposalExecutionEngine.sol";
import "./ZoraHelpers.sol";

// Implements proposals auctioning an NFT on Zora. Inherited by the `ProposalExecutionEngine`.
// This contract will be delegatecall'ed into by `Party` proxy instances.
contract ListOnZoraProposal is ZoraHelpers {
    using LibRawResult for bytes;
    using LibSafeERC721 for IERC721;
    using LibSafeCast for uint256;

    enum ZoraStep {
        // Proposal has not been executed yet and should be listed on Zora.
        None,
        // Proposal was previously executed and the NFT is already listed on Zora.
        ListedOnZora
    }

    // ABI-encoded `proposalData` passed into execute.
    struct ZoraProposalData {
        // The minimum bid (ETH) for the NFT.
        uint256 listPrice;
        // How long before the auction can be cancelled if no one bids.
        uint40 timeout;
        // How long the auction lasts once a person bids on it.
        uint40 duration;
        // The token contract of the NFT being listed.
        IERC721 token;
        // The token ID of the NFT being listed.
        uint256 tokenId;
    }

    error ZoraListingNotExpired(uint256 auctionId, uint40 expiry);

    event ZoraAuctionCreated(
        uint256 auctionId,
        IERC721 token,
        uint256 tokenId,
        uint256 startingPrice,
        uint40 duration,
        uint40 timeoutTime
    );
    event ZoraAuctionExpired(uint256 auctionId, uint256 expiry);
    event ZoraAuctionSold(uint256 auctionId);
    event ZoraAuctionFailed(uint256 auctionId);

    // keccak256(abi.encodeWithSignature('Error(string)', "Auction hasn't begun"))
    bytes32 internal constant AUCTION_HASNT_BEGUN_ERROR_HASH =
        0x54a53788b7942d79bb6fcd40012c5e867208839fa1607e1f245558ee354e9565;
    // keccak256(abi.encodeWithSignature('Error(string)', "Auction doesn't exit"))
    bytes32 internal constant AUCTION_DOESNT_EXIST_ERROR_HASH =
        0x474ba0184a7cd5de777156a56f3859150719340a6974b6ee50f05c58139f4dc2;
    /// @notice Zora auction house contract.
    IZoraAuctionHouse public immutable ZORA;
    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    // Set immutables.
    constructor(IGlobals globals, IZoraAuctionHouse zoraAuctionHouse) {
        ZORA = zoraAuctionHouse;
        _GLOBALS = globals;
    }

    // Auction an NFT we hold on Zora.
    // Calling this the first time will create a Zora auction.
    // Calling this the second time will either cancel or finalize the auction.
    function _executeListOnZora(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal returns (bytes memory nextProgressData) {
        ZoraProposalData memory data = abi.decode(params.proposalData, (ZoraProposalData));
        // If there is progressData passed in, we're on the first step,
        // otherwise parse the first word of the progressData as the current step.
        ZoraStep step = params.progressData.length == 0
            ? ZoraStep.None
            : abi.decode(params.progressData, (ZoraStep));
        if (step == ZoraStep.None) {
            // Proposal hasn't executed yet.
            {
                // Clamp the Zora auction duration to the global minimum and maximum.
                uint40 minDuration = uint40(
                    _GLOBALS.getUint256(LibGlobals.GLOBAL_ZORA_MIN_AUCTION_DURATION)
                );
                uint40 maxDuration = uint40(
                    _GLOBALS.getUint256(LibGlobals.GLOBAL_ZORA_MAX_AUCTION_DURATION)
                );
                if (minDuration != 0 && data.duration < minDuration) {
                    data.duration = minDuration;
                } else if (maxDuration != 0 && data.duration > maxDuration) {
                    data.duration = maxDuration;
                }
                // Clamp the Zora auction timeout to the global maximum.
                uint40 maxTimeout = uint40(
                    _GLOBALS.getUint256(LibGlobals.GLOBAL_ZORA_MAX_AUCTION_TIMEOUT)
                );
                if (maxTimeout != 0 && data.timeout > maxTimeout) {
                    data.timeout = maxTimeout;
                }
            }
            // Create a Zora auction for the NFT.
            uint256 auctionId = _createZoraAuction(
                data.listPrice,
                data.timeout,
                data.duration,
                data.token,
                data.tokenId
            );
            return
                abi.encode(
                    ZoraStep.ListedOnZora,
                    ZoraProgressData({
                        auctionId: auctionId,
                        minExpiry: (block.timestamp + data.timeout).safeCastUint256ToUint40()
                    })
                );
        }
        assert(step == ZoraStep.ListedOnZora);
        (, ZoraProgressData memory pd) = abi.decode(
            params.progressData,
            (ZoraStep, ZoraProgressData)
        );
        _settleZoraAuction(pd.auctionId, pd.minExpiry, data.token, data.tokenId);
        // Nothing left to do.
        return "";
    }

    // Transfer and create a Zora auction for the `token` + `tokenId`.
    function _createZoraAuction(
        // The minimum bid.
        uint256 listPrice,
        // How long the auction must wait for the first bid.
        uint40 timeout,
        // How long the auction will run for once a bid has been placed.
        uint40 duration,
        IERC721 token,
        uint256 tokenId
    ) internal override returns (uint256 auctionId) {
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
        emit ZoraAuctionCreated(
            auctionId,
            token,
            tokenId,
            listPrice,
            duration,
            uint40(block.timestamp + timeout)
        );
    }

    // Either cancel or finalize a Zora auction.
    function _settleZoraAuction(
        uint256 auctionId,
        uint40 minExpiry,
        IERC721 token,
        uint256 tokenId
    ) internal override returns (ZoraAuctionStatus statusCode) {
        // Getting the state of an auction is super expensive so it seems
        // cheaper to just let `endAuction()` fail and react to the error.
        try ZORA.endAuction(auctionId) {
            // Check whether auction cancelled due to a failed transfer during
            // settlement by seeing if we now possess the NFT.
            if (token.safeOwnerOf(tokenId) == address(this)) {
                emit ZoraAuctionFailed(auctionId);
                return ZoraAuctionStatus.Cancelled;
            }
        } catch (bytes memory errData) {
            bytes32 errHash = keccak256(errData);
            if (errHash == AUCTION_HASNT_BEGUN_ERROR_HASH) {
                // No bids placed.
                // Cancel if we're past the timeout.
                if (minExpiry > uint40(block.timestamp)) {
                    revert ZoraListingNotExpired(auctionId, minExpiry);
                }
                ZORA.cancelAuction(auctionId);
                emit ZoraAuctionExpired(auctionId, minExpiry);
                return ZoraAuctionStatus.Expired;
            } else if (errHash != AUCTION_DOESNT_EXIST_ERROR_HASH) {
                // Otherwise, we should get an auction doesn't exist error,
                // because someone else must have called `endAuction()`.
                // If we didn't then something is wrong, so revert.
                errData.rawRevert();
            }
            // Already ended by someone else. Nothing to do.
        }
        emit ZoraAuctionSold(auctionId);
        return ZoraAuctionStatus.Sold;
    }
}
