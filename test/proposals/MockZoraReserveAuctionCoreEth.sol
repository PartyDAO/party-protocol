// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/tokens/IERC20.sol";
import "../../contracts/tokens/IERC721.sol";
import "../../contracts/vendor/markets/IReserveAuctionCoreEth.sol";

contract MockZoraReserveAuctionCoreEth is IReserveAuctionCoreEth {
    uint256 public lastAuctionId = 8000;
    uint256 public timeBuffer = 15 minutes;

    function createAuction(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _duration,
        uint256 _reservePrice,
        address _sellerFundsRecipient,
        uint256 _startTime
    ) external override {}

    function createBid(address, uint256) external payable override {
        revert("no implementado");
    }

    function setAuctionReservePrice(address, uint256, uint256) external pure override {
        revert("no implementation");
    }

    function cancelAuction(address, uint256) external pure override {
        revert("no implementado");
    }

    function auctionForNFT(address, uint256) external pure override returns (Auction calldata) {
        revert("no implementado");
    }

    function settleAuction(address, uint256) external pure override {
        revert("no implementation");
    }

    function erc721TransferHelper() external pure override returns (BaseTransferHelper) {
        return BaseTransferHelper(address(0));
    }
}
