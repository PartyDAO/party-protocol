// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./IOperator.sol";
import "../party/Party.sol";
import "../tokens/IERC721.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibAddress.sol";
import "../utils/LibSafeERC721.sol";
import "openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @notice An operator that can be used to buy NFTs from a collection.
contract CollectionBatchBuyOperator is IOperator {
    using LibRawResult for bytes;
    using LibSafeERC721 for IERC721;
    using LibAddress for address payable;

    struct CollectionBatchBuyOperationData {
        /// The contract of NFTs to buy.
        IERC721 nftContract;
        /// The merkle root of the token IDs that can be bought. If null,
        /// allow any token ID in the collection can be bought.
        bytes32 nftTokenIdsMerkleRoot;
        // Maximum amount this crowdfund will pay for an NFT.
        uint256 maximumPrice;
        // Minimum number of tokens that must be purchased. If this limit is
        // not reached, the batch buy will fail.
        uint256 minTokensBought;
        // Minimum amount of ETH that must be used to buy the tokens. If this
        // amount is not reached, the batch buy will fail.
        uint256 minTotalEthUsed;
    }

    struct TokenToBuy {
        // The token ID of the NFT to buy.
        uint256 tokenId;
        // The price of the token. This cannot be greater than `maximumPrice`.
        uint96 price;
        // The proof needed to verify that the token ID is included in the
        // `nftTokenIdsMerkleRoot` (if it is not null).
        bytes32[] proof;
    }

    struct BuyCall {
        // The contract to call to buy the NFTs in `tokensToBuy`.
        address payable target;
        // The calldata to call `target` with to buy the NFTs in `tokensToBuy`.
        bytes data;
        // The tokens to try buying with this call.
        TokenToBuy[] tokensToBuy;
    }

    struct CollectionBatchBuyExecutionData {
        // The calls made to buy the NFTs. Each call has a target, data, and
        // the tokens to buy in that call.
        BuyCall[] calls;
        // The total number of tokens that can be bought in this batch buy. This
        // should be equal to the sum of the each `tokensToBuy` in `calls`.
        uint256 numOfTokens;
    }

    event CollectionBatchBuyOperationExecuted(
        Party party,
        IERC721 token,
        uint256[] tokenIdsBought,
        uint256 totalEthUsed
    );

    error NothingBoughtError();
    error InvalidMinTokensBoughtError(uint256 minTokensBought);
    error InvalidTokenIdError();
    error NotEnoughTokensBoughtError(uint256 tokensBought, uint256 minTokensBought);
    error NotEnoughEthUsedError(uint256 ethUsed, uint256 minTotalEthUsed);
    error MaximumPriceError(uint256 callValue, uint256 maximumPrice);
    error CallProhibitedError(address target, bytes data);
    error NumOfTokensCannotBeLessThanMin(uint256 numOfTokens, uint256 min);
    error EthUsedForFailedBuyError(uint256 expectedEthUsed, uint256 actualEthUsed);

    function execute(
        bytes memory operatorData,
        bytes memory executionData,
        address executor,
        bool allowOperatorsToSpendPartyEth
    ) external payable {
        // Decode the operator data.
        CollectionBatchBuyOperationData memory op = abi.decode(
            operatorData,
            (CollectionBatchBuyOperationData)
        );

        // Decode the execution data.
        CollectionBatchBuyExecutionData memory ex = abi.decode(
            executionData,
            (CollectionBatchBuyExecutionData)
        );

        if (op.minTokensBought == 0) {
            // Must buy at least one token.
            revert InvalidMinTokensBoughtError(0);
        }

        if (ex.numOfTokens < op.minTokensBought) {
            // The number of tokens to buy must be greater than or equal to the
            // minimum number of tokens to buy.
            revert NumOfTokensCannotBeLessThanMin(ex.numOfTokens, op.minTokensBought);
        }

        // Lengths of arrays are updated at the end.
        uint256[] memory tokenIds = new uint256[](ex.numOfTokens);

        uint96 totalEthUsed;
        uint256 tokensBought;
        for (uint256 i; i < ex.calls.length; ++i) {
            BuyCall memory call = ex.calls[i];

            uint96 callValue;
            for (uint256 j; j < call.tokensToBuy.length; ++j) {
                TokenToBuy memory tokenToBuy = call.tokensToBuy[j];

                if (op.nftTokenIdsMerkleRoot != bytes32(0)) {
                    // Verify the token ID is in the merkle tree.
                    _verifyTokenId(tokenToBuy.tokenId, op.nftTokenIdsMerkleRoot, tokenToBuy.proof);
                }

                // Check that the call value is under the maximum price.
                uint96 price = tokenToBuy.price;
                if (price > op.maximumPrice) {
                    revert MaximumPriceError(price, op.maximumPrice);
                }

                // Add the price to the total value used for the call.
                callValue += price;
            }

            uint256 balanceBefore = address(this).balance;
            {
                // Execute the call to buy the NFT.
                (bool success, ) = _buy(call.target, callValue, call.data);

                if (!success) continue;
            }

            {
                uint96 ethUsed;
                for (uint256 j; j < call.tokensToBuy.length; ++j) {
                    uint256 tokenId = call.tokensToBuy[j].tokenId;
                    uint96 price = call.tokensToBuy[j].price;

                    // Check whether the NFT was successfully bought.
                    if (op.nftContract.safeOwnerOf(tokenId) == address(this)) {
                        ethUsed += price;
                        ++tokensBought;

                        // Add the token to the list of tokens to finalize.
                        tokenIds[tokensBought - 1] = tokenId;
                    }
                }

                // Check ETH spent for call is what was expected.
                uint256 actualEthUsed = balanceBefore - address(this).balance;
                if (ethUsed != actualEthUsed) {
                    revert EthUsedForFailedBuyError(ethUsed, actualEthUsed);
                }

                totalEthUsed += ethUsed;
            }
        }

        // This is to prevent this crowdfund from finalizing a loss if nothing
        // was attempted to be bought (ie. `tokenIds` is empty) or all NFTs were
        // bought for free.
        if (totalEthUsed == 0) revert NothingBoughtError();

        // Check number of tokens bought is not less than the minimum.
        if (tokensBought < op.minTokensBought) {
            revert NotEnoughTokensBoughtError(tokensBought, op.minTokensBought);
        }

        // Check total ETH used is not less than the minimum.
        if (totalEthUsed < op.minTotalEthUsed) {
            revert NotEnoughEthUsedError(totalEthUsed, op.minTotalEthUsed);
        }

        assembly {
            // Update length of `tokenIds`
            mstore(tokenIds, tokensBought)
        }

        // Transfer the NFTs to the party.
        for (uint256 i; i < tokenIds.length; ++i) {
            op.nftContract.safeTransferFrom(address(this), msg.sender, tokenIds[i]);
        }

        uint256 unusedEth = msg.value - totalEthUsed;
        if (unusedEth > 0) {
            if (allowOperatorsToSpendPartyEth) {
                // Transfer unused ETH to the party.
                payable(msg.sender).transferEth(unusedEth);
            } else {
                // Transfer unused ETH to the executor.
                payable(executor).transferEth(unusedEth);
            }
        }

        emit CollectionBatchBuyOperationExecuted(
            Party(payable(msg.sender)),
            op.nftContract,
            tokenIds,
            totalEthUsed
        );
    }

    function _buy(
        address payable callTarget,
        uint96 callValue,
        bytes memory callData
    ) private returns (bool success, bytes memory revertData) {
        // Check that call is not re-entering.
        if (callTarget == address(this)) {
            revert CallProhibitedError(callTarget, callData);
        }
        // Execute the call to buy the NFT.
        (success, revertData) = callTarget.call{ value: callValue }(callData);
    }

    function _verifyTokenId(uint256 tokenId, bytes32 root, bytes32[] memory proof) private pure {
        bytes32 leaf;
        assembly {
            mstore(0x00, tokenId)
            leaf := keccak256(0x00, 0x20)
        }

        if (!MerkleProof.verify(proof, root, leaf)) revert InvalidTokenIdError();
    }
}
