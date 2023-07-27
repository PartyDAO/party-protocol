// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { IGlobals } from "../globals/IGlobals.sol";
import { LibGlobals } from "../globals/LibGlobals.sol";
import { IERC721 } from "../tokens/IERC721.sol";
import { LibSafeCast } from "../utils/LibSafeCast.sol";
import { IReserveAuctionCoreEth, BaseTransferHelper } from "../vendor/markets/IReserveAuctionCoreEth.sol";
import { IProposalExecutionEngine } from "./IProposalExecutionEngine.sol";
import { ZoraHelpers } from "./ZoraHelpers.sol";

// Implements proposals auctioning an NFT on Zora. Inherited by the `ProposalExecutionEngine`.
// This contract will be delegatecall'ed into by `Party` proxy instances.
contract ListOnZoraProposal is ZoraHelpers {
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
        address token;
        // The token ID of the NFT being listed.
        uint256 tokenId;
    }

    error ZoraListingNotExpired(address token, uint256 tokenid, uint40 expiry);
    error ZoraListingLive(address token, uint256 tokenId, uint256 auctionEndTime);

    event ZoraAuctionCreated(
        address token,
        uint256 tokenId,
        uint256 startingPrice,
        uint40 duration,
        uint40 timeoutTime
    );
    event ZoraAuctionExpired(address token, uint256 tokenid, uint256 expiry);
    event ZoraAuctionSold(address token, uint256 tokenid);

    /// @notice Zora auction house contract.
    IReserveAuctionCoreEth public immutable ZORA;
    /// @notice Zora ERC721 tranfer helper for approvals
    BaseTransferHelper public immutable ZORA_TRANSFER_HELPER;
    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    /// @notice Use a constant, non-overlapping slot offset for the `ZoraProposalStorage` bucket
    uint256 private constant _ZORA_PROPOSAL_STORAGE_SLOT =
        uint256(keccak256("ListOnZoraProposal.Storage"));
    /// @notice The storage struct for this contract
    struct ZoraProposalStorage {
        // Whether the Zora auction module has been approved (per party)
        bool zoraAuctionModuleApproved;
    }

    // Set immutables.
    constructor(IGlobals globals, IReserveAuctionCoreEth zora) {
        ZORA = zora;
        ZORA_TRANSFER_HELPER = ZORA.erc721TransferHelper();
        _GLOBALS = globals;
    }

    // Auction an NFT we hold on Zora.
    // Calling this the first time will create a Zora auction.
    // Calling this the second time will either cancel or finalize the auction.
    function _executeListOnZora(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal returns (bytes memory nextProgressData) {
        ZoraProposalData memory data = abi.decode(params.proposalData, (ZoraProposalData));
        // If there is no progressData passed in, we're on the first step,
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
            _createZoraAuction(
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
                        minExpiry: (block.timestamp + data.timeout).safeCastUint256ToUint40()
                    })
                );
        }
        assert(step == ZoraStep.ListedOnZora);
        (, ZoraProgressData memory pd) = abi.decode(
            params.progressData,
            (ZoraStep, ZoraProgressData)
        );
        _settleZoraAuction(pd.minExpiry, data.token, data.tokenId);
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
        address token,
        uint256 tokenId
    ) internal virtual override {
        ZoraProposalStorage storage s = _getZoraProposalStorage();
        if (!s.zoraAuctionModuleApproved) {
            ZORA_TRANSFER_HELPER.ZMM().setApprovalForModule(address(ZORA), true);
            s.zoraAuctionModuleApproved = true;
        }
        IERC721(token).approve(address(ZORA_TRANSFER_HELPER), tokenId);

        ZORA.createAuction(token, tokenId, duration, listPrice, address(this), block.timestamp);
        emit ZoraAuctionCreated(
            token,
            tokenId,
            listPrice,
            duration,
            uint40(block.timestamp + timeout)
        );
    }

    // Either cancel or finalize a Zora auction.
    function _settleZoraAuction(
        uint40 minExpiry,
        address token,
        uint256 tokenId
    ) internal override returns (ZoraAuctionStatus statusCode) {
        IReserveAuctionCoreEth.Auction memory auction = ZORA.auctionForNFT(token, tokenId);
        if (auction.seller != address(this)) {
            // Auction has already been settled
            emit ZoraAuctionSold(token, tokenId);
            return ZoraAuctionStatus.Sold;
        }
        if (auction.firstBidTime == 0) {
            if (minExpiry > block.timestamp) {
                revert ZoraListingNotExpired(token, tokenId, minExpiry);
            }
            // minExpiry passed with no bids
            ZORA.cancelAuction(token, tokenId);
            IERC721(token).approve(address(0), tokenId);
            emit ZoraAuctionExpired(token, tokenId, minExpiry);
            return ZoraAuctionStatus.Expired;
        } else {
            uint32 auctionEndTime = auction.firstBidTime + auction.duration;
            if (block.timestamp >= auctionEndTime) {
                ZORA.settleAuction(token, tokenId);
                emit ZoraAuctionSold(token, tokenId);
                return ZoraAuctionStatus.Sold;
            } else {
                // Auction live
                revert ZoraListingLive(token, tokenId, auctionEndTime);
            }
        }
    }

    /// @notice Retrieve the explicit storage bucket for the `ZoraProposalStorage` struct.
    function _getZoraProposalStorage() private pure returns (ZoraProposalStorage storage stor) {
        uint256 slot = _ZORA_PROPOSAL_STORAGE_SLOT;
        assembly {
            stor.slot := slot
        }
    }
}
