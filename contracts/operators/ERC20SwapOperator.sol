// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { IOperator } from "./IOperator.sol";
import { IGlobals } from "../globals/IGlobals.sol";
import { LibGlobals } from "../globals/LibGlobals.sol";
import { Party } from "../party/Party.sol";
import { IERC20 } from "../tokens/IERC20.sol";
import { LibAddress } from "../utils/LibAddress.sol";
import { LibERC20Compat } from "../utils/LibERC20Compat.sol";
import { LibRawResult } from "../utils/LibRawResult.sol";

/// @notice An operator that can be used to perform swaps between tokens on
///         behalf of a party.
contract ERC20SwapOperator is IOperator {
    using LibAddress for address payable;
    using LibRawResult for bytes;
    using LibERC20Compat for IERC20;

    event ERC20SwapOperationExecuted(
        // Party that executed the operation
        Party party,
        // Token that is swapped
        IERC20 fromToken,
        // Token that is received from the swap
        IERC20 toToken,
        // Amount of tokens that are swapped
        uint256 amount,
        // Amount of tokens that are received from the swap
        uint256 receivedAmount
    );

    event TargetAllowedSet(address target, bool isAllowed);

    // Parameters defining at time of operation created
    struct ERC20SwapOperationData {
        // The token to swap.
        IERC20 fromToken;
        // The token to receive.
        IERC20 toToken;
        // The minimum amount of `toToken` to receive.
        uint256 minReceivedAmount;
    }

    // Parameters defining at time of operation execution
    struct ERC20SwapExecutionData {
        // The target contract to call.
        address payable target;
        // The calldata to call the target with.
        bytes callData;
        // Whether the received amount should be received by the Party directly
        // or indirectly via this operator which will transfer it to the Party.
        bool isReceivedDirectly;
    }

    error InsufficientReceivedAmountError(uint256 receivedAmount, uint256 minToTokenAmount);
    error OnlyPartyDaoError(address notDao, address partyDao);
    error UnauthorizedTargetError(address payable target);
    error InKindSwap();

    IERC20 private constant ETH_TOKEN_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    /// @notice Contracts allowed to perform swaps. Should be mostly/entirely
    ///         approved aggregators although can be any contract.
    mapping(address target => bool isAllowed) public isTargetAllowed;

    modifier onlyPartyDao() {
        {
            address partyDao = _GLOBALS.getAddress(LibGlobals.GLOBAL_DAO_WALLET);
            if (msg.sender != partyDao) {
                revert OnlyPartyDaoError(msg.sender, partyDao);
            }
        }
        _;
    }

    constructor(IGlobals globals, address[] memory allowedTargets) {
        // Set the immutable globals.
        _GLOBALS = globals;

        // Set the initial allowed targets.
        for (uint256 i = 0; i < allowedTargets.length; i++) {
            isTargetAllowed[allowedTargets[i]] = true;
        }
    }

    /// @notice Set the allowed targets that can be used to perform swaps. Can
    ///         only be called by the PartyDAO multisig.
    /// @param target The target contract address.
    /// @param isAllowed Whether the target is allowed.
    function setTargetAllowed(address target, bool isAllowed) external onlyPartyDao {
        isTargetAllowed[target] = isAllowed;

        emit TargetAllowedSet(target, isAllowed);
    }

    /// @inheritdoc IOperator
    function execute(
        bytes memory operatorData,
        bytes memory executionData,
        address
    ) external payable {
        // Decode the operator data.
        ERC20SwapOperationData memory op = abi.decode(operatorData, (ERC20SwapOperationData));

        // Decode the execution data.
        ERC20SwapExecutionData memory ex = abi.decode(executionData, (ERC20SwapExecutionData));

        // Check if the target is allowed.
        if (!isTargetAllowed[ex.target]) revert UnauthorizedTargetError(ex.target);

        if (op.fromToken == op.toToken) {
            // Doesn't make sense to swap a token for the same token.
            revert InKindSwap();
        }

        // Get the amount of tokens sent to this contract. This contract should
        // not hold any token balances before the swap is performed, although if
        // it does the next Party swapping that token will receive more back
        // than expected.
        uint256 amount;
        if (op.fromToken == ETH_TOKEN_ADDRESS) {
            amount = address(this).balance;
        } else {
            amount = op.fromToken.balanceOf(address(this));

            // Give target permission to spend `fromToken` on behalf of this
            // contract to swap.
            op.fromToken.compatApprove(ex.target, amount);
        }

        // Get the expected receiver of the `toToken`.
        address payable receiver = ex.isReceivedDirectly
            ? payable(msg.sender)
            : payable(address(this));

        // Get the balance of the `toToken` before the swap. Ignore if the
        // `toToken` is not received directly, the intended behavior is to
        // transfer any dust or "stray" balances this contract may have to the
        // Party.
        uint256 toTokenBalanceBefore;
        if (ex.isReceivedDirectly) {
            if (op.toToken == ETH_TOKEN_ADDRESS) {
                toTokenBalanceBefore = address(msg.sender).balance;
            } else {
                toTokenBalanceBefore = op.toToken.balanceOf(address(msg.sender));
            }
        }

        // Perform the swap.
        {
            uint256 value = op.fromToken == ETH_TOKEN_ADDRESS ? amount : 0;
            (bool success, bytes memory res) = ex.target.call{ value: value }(ex.callData);
            if (!success) {
                res.rawRevert();
            }
        }

        // Calculate the amount of `toToken` received.
        uint256 receivedAmount = (
            op.toToken == ETH_TOKEN_ADDRESS ? receiver.balance : op.toToken.balanceOf(receiver)
        ) - toTokenBalanceBefore;

        // Check that the received amount is at least the minimum specified.
        if (receivedAmount < op.minReceivedAmount) {
            revert InsufficientReceivedAmountError(receivedAmount, op.minReceivedAmount);
        }

        // Ensure reset allowances. Besides being a precaution, this is also
        // ensures compatibility with tokens require allowance to be zero before
        // approvals (e.g. USDT).
        if (op.fromToken != ETH_TOKEN_ADDRESS) {
            op.fromToken.compatApprove(ex.target, 0);
        }

        // Transfer the received tokens to the Party if not received directly.
        if (!ex.isReceivedDirectly && receivedAmount != 0) {
            if (op.toToken == ETH_TOKEN_ADDRESS) {
                payable(msg.sender).transferEth(receivedAmount);
            } else {
                op.toToken.compatTransfer(msg.sender, receivedAmount);
            }
        }

        // Transfer any remaining `fromTokens` back to the Party.
        uint256 refundAmount = op.fromToken == ETH_TOKEN_ADDRESS
            ? receiver.balance
            : op.fromToken.balanceOf(receiver);

        if (refundAmount != 0) {
            if (op.fromToken == ETH_TOKEN_ADDRESS) {
                payable(msg.sender).transferEth(refundAmount);
            } else {
                op.fromToken.compatTransfer(msg.sender, refundAmount);
            }
        }

        emit ERC20SwapOperationExecuted(
            Party(payable(msg.sender)),
            op.fromToken,
            op.toToken,
            amount,
            receivedAmount
        );
    }

    receive() external payable {}
}
