// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./IProposalExecutionEngine.sol";
import "../operators/IOperator.sol";
import "../utils/LibERC20Compat.sol";
import "../tokens/IERC721.sol";
import "../tokens/IERC20.sol";
import "../tokens/IERC1155.sol";

/// @notice A proposal that can be used to execute an operation through an
///         operator which performs a specific action on the party's behalf.
contract OperatorProposal {
    using LibERC20Compat for IERC20;

    enum OperatorListingTokenType {
        ETH,
        ERC20,
        ERC721,
        ERC1155
    }

    struct AssetData {
        OperatorListingTokenType tokenType;
        address token;
        uint256 tokenId;
        uint256 amount;
    }

    struct OperatorProposalData {
        // Addresses that are allowed to execute the proposal and decide what
        // calldata used by the operator proposal at the time of execution.
        address[] allowedExecutors;
        // Assets and amounts to transfer to the operator contract to use on
        // behalf of the party.
        AssetData[] assets;
        // The operator contract that will be used to execute the proposal.
        IOperator operator;
        // The calldata that will be used by the operator contract to execute the proposal.
        bytes operatorData;
    }

    event OperationExecuted(address executor);

    error NotAllowedToExecute(address executor, address[] allowedExecutors);
    error NotEnoughEthError(uint256 operatorValue, uint256 ethAvailable);

    function _executeOperation(
        IProposalExecutionEngine.ExecuteProposalParams memory params,
        bool allowOperatorsToSpendPartyEth
    ) internal returns (bytes memory nextProgressData) {
        // Decode the proposal data.
        OperatorProposalData memory data = abi.decode(params.proposalData, (OperatorProposalData));
        (uint256 allowedExecutorsIndex, bytes memory executionData) = abi.decode(
            params.extraData,
            (uint256, bytes)
        );

        // Check that the caller is an allowed executor.
        _assertCallerIsAllowedToExecute(msg.sender, data.allowedExecutors, allowedExecutorsIndex);

        // Transfer assets to the operator contract to use on behalf of the party.
        uint256 ethToTransfer;
        for (uint256 i; i < data.assets.length; ++i) {
            AssetData memory asset = data.assets[i];
            if (asset.tokenType == OperatorListingTokenType.ETH) {
                ethToTransfer += asset.amount;
            } else if (asset.tokenType == OperatorListingTokenType.ERC20) {
                IERC20(asset.token).compatTransfer(address(data.operator), asset.amount);
            } else if (asset.tokenType == OperatorListingTokenType.ERC721) {
                IERC721(asset.token).safeTransferFrom(
                    address(this),
                    address(data.operator),
                    asset.tokenId
                );
            } else if (asset.tokenType == OperatorListingTokenType.ERC1155) {
                IERC1155(asset.token).safeTransferFrom(
                    address(this),
                    address(data.operator),
                    asset.tokenId,
                    asset.amount,
                    ""
                );
            }
        }

        // Check whether operator can spend party's ETH balance. Otherwise, it
        // can only spend ETH sent with the transaction from the executor.
        if (!allowOperatorsToSpendPartyEth && ethToTransfer > msg.value) {
            revert NotEnoughEthError(ethToTransfer, msg.value);
        }

        // Execute the operation.
        data.operator.execute{ value: ethToTransfer }(
            data.operatorData,
            executionData,
            msg.sender,
            allowOperatorsToSpendPartyEth
        );

        // Nothing left to do.
        return "";
    }

    function _assertCallerIsAllowedToExecute(
        address caller,
        address[] memory allowedExecutors,
        uint256 allowedExecutorsIndex
    ) private pure {
        // If there are no allowed executors, then anyone can execute.
        if (allowedExecutors.length == 0) return;

        // Check if the caller is an allowed executor.
        if (caller != allowedExecutors[allowedExecutorsIndex])
            revert NotAllowedToExecute(caller, allowedExecutors);
    }
}
