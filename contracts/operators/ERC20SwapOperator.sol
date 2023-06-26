// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./IOperator.sol";
import "../party/Party.sol";
import "../tokens/IERC20.sol";
import "../utils/LibAddress.sol";
import "../utils/LibERC20Compat.sol";
import "../utils/LibRawResult.sol";

/// @notice An operator that can be used to perform swaps between tokens on
///         behalf of a party.
contract ERC20SwapOperator is IOperator {
    using LibAddress for address payable;
    using LibRawResult for bytes;
    using LibERC20Compat for IERC20;

    event ERC20SwapOperationExecuted(
        Party party,
        IERC20 fromToken,
        IERC20 toToken,
        uint256 amount,
        uint256 receivedAmount
    );

    struct ERC20SwapOperationData {
        IERC20 fromToken;
        IERC20 toToken;
        uint256 minReceivedAmount;
    }

    struct ERC20SwapExecutionData {
        address payable target;
        bytes callData;
    }

    error InsufficientReceivedAmountError(uint256 receivedAmount, uint256 minToTokenAmount);
    error OnlyPartyDaoError(address notDao, address partyDao);
    error UnauthorizedTargetError(address payable target);

    IERC20 private constant ETH_TOKEN_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    /// @notice Contracts allowed to perform swaps. Should be mostly/entirely
    ///         approved aggregators although can be any contract.
    mapping(address target => bool isAllowed) public isTargetAllowed;

    // Last recorded balance of each token held by this contract. This is used
    // to calculate the amount of tokens sent to this contract. Learn more about
    // this in the `execute()` method.
    mapping(IERC20 => uint256) private _storedBalances;

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
    }

    /// @inheritdoc IOperator
    function execute(
        bytes memory operatorData,
        bytes memory executionData,
        address,
        bool
    ) external payable {
        // Decode the operator data.
        ERC20SwapOperationData memory op = abi.decode(operatorData, (ERC20SwapOperationData));

        // Decode the execution data.
        ERC20SwapExecutionData memory ex = abi.decode(executionData, (ERC20SwapExecutionData));

        // Check if the target is allowed.
        if (!isTargetAllowed[ex.target]) revert UnauthorizedTargetError(ex.target);

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
            op.fromToken.approve(ex.target, amount);
        }

        // Perform the swap.
        {
            uint256 value = op.fromToken == ETH_TOKEN_ADDRESS ? amount : 0;
            (bool success, bytes memory res) = ex.target.call{ value: value }(ex.callData);
            if (!success) {
                res.rawRevert();
            }
        }

        // Get the received amount.
        uint256 receivedAmount = op.toToken == ETH_TOKEN_ADDRESS
            ? address(this).balance
            : op.toToken.balanceOf(address(this));

        // Check that the received amount is at least the minimum specified.
        if (receivedAmount < op.minReceivedAmount) {
            revert InsufficientReceivedAmountError(receivedAmount, op.minReceivedAmount);
        }

        // Ensure reset allowances. Besides being a precaution, this is also
        // ensures compatibility with tokens require allowance to be zero before
        // approvals (e.g. USDT).
        if (op.fromToken != ETH_TOKEN_ADDRESS) {
            op.fromToken.approve(ex.target, 0);
        }

        // Transfer the received tokens to the party.
        if (receivedAmount != 0) {
            if (op.toToken == ETH_TOKEN_ADDRESS) {
                payable(msg.sender).transferEth(receivedAmount);
            } else {
                op.toToken.compatTransfer(msg.sender, receivedAmount);
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
}
