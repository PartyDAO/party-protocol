// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "contracts/operators/ERC20SwapOperator.sol";
import "contracts/globals/Globals.sol";
import "contracts/tokens/ERC721Receiver.sol";

import "../DummyERC20.sol";
import "../TestUtils.sol";

IERC20 constant ETH_TOKEN_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

contract ERC20SwapOperatorTest is Test, TestUtils, ERC721Receiver {
    event ERC20SwapOperationExecuted(
        Party party,
        IERC20 fromToken,
        IERC20 toToken,
        uint256 amount,
        uint256 receivedAmount
    );

    event TargetAllowedSet(address target, bool isAllowed);

    address multisig;
    Globals globals;
    ERC20SwapOperator operator;
    DummyAggregator aggregator;
    DummyERC20 fromToken;
    DummyERC20 toToken;

    constructor() {
        multisig = _randomAddress();
        globals = new Globals(multisig);
        aggregator = new DummyAggregator();

        vm.prank(multisig);
        globals.setAddress(LibGlobals.GLOBAL_DAO_WALLET, multisig);

        address[] memory allowedTargets = new address[](1);
        allowedTargets[0] = address(aggregator);

        operator = new ERC20SwapOperator(globals, allowedTargets);
        fromToken = new DummyERC20();
        toToken = new DummyERC20();
    }

    function test_ERC20Swap_works() public {
        // Mint tokens to swap
        fromToken.deal(address(operator), 100e18);

        // Setup operation
        ERC20SwapOperator.ERC20SwapOperationData memory operationData = ERC20SwapOperator
            .ERC20SwapOperationData({
                fromToken: fromToken,
                toToken: toToken,
                minReceivedAmount: 95e18
            });

        ERC20SwapOperator.ERC20SwapExecutionData memory executionData = ERC20SwapOperator
            .ERC20SwapExecutionData({
                target: payable(address(aggregator)),
                callData: abi.encodeWithSelector(
                    aggregator.swap.selector,
                    fromToken,
                    toToken,
                    100e18,
                    address(operator)
                ),
                isReceivedDirectly: false
            });

        // Execute operation
        vm.expectEmit(true, true, true, true);
        emit ERC20SwapOperationExecuted(
            Party(payable(address(this))),
            fromToken,
            toToken,
            100e18,
            99e18
        );
        operator.execute(abi.encode(operationData), abi.encode(executionData), address(0));

        assertEq(toToken.balanceOf(address(this)), 99e18);
        assertEq(fromToken.balanceOf(address(this)), 0);
        assertEq(toToken.balanceOf(address(operator)), 0);
        assertEq(fromToken.balanceOf(address(operator)), 0);
        assertEq(fromToken.allowance(address(operator), address(aggregator)), 0);
    }

    function test_ERC20Swap_multiple() public {
        for (uint256 i; i < 5; ++i) {
            test_ERC20Swap_works();

            // Burn received tokens to reset balances for next swap
            toToken.transfer(address(0), toToken.balanceOf(address(this)));
        }
    }

    function test_ERC20Swap_canReceiveDirectly_withoutPreviousBalance() public {
        // Mint tokens to swap
        fromToken.deal(address(operator), 100e18);

        // Setup operation
        ERC20SwapOperator.ERC20SwapOperationData memory operationData = ERC20SwapOperator
            .ERC20SwapOperationData({
                fromToken: fromToken,
                toToken: toToken,
                minReceivedAmount: 95e18
            });

        ERC20SwapOperator.ERC20SwapExecutionData memory executionData = ERC20SwapOperator
            .ERC20SwapExecutionData({
                target: payable(address(aggregator)),
                callData: abi.encodeWithSelector(
                    aggregator.swap.selector,
                    fromToken,
                    toToken,
                    100e18,
                    address(this)
                ),
                isReceivedDirectly: true
            });

        // Execute operation
        vm.expectEmit(true, true, true, true);
        emit ERC20SwapOperationExecuted(
            Party(payable(address(this))),
            fromToken,
            toToken,
            100e18,
            99e18
        );
        operator.execute(abi.encode(operationData), abi.encode(executionData), address(0));

        assertEq(toToken.balanceOf(address(this)), 99e18);
        assertEq(fromToken.balanceOf(address(this)), 0);
        assertEq(toToken.balanceOf(address(operator)), 0);
        assertEq(fromToken.balanceOf(address(operator)), 0);
        assertEq(fromToken.allowance(address(operator), address(aggregator)), 0);
    }

    function test_ERC20Swap_canReceiveDirectly_withPreviousBalance() public {
        // Setup non-zero balance of to token to this contract
        uint256 toTokenBalanceBefore = _randomUint256();
        toToken.deal(address(this), toTokenBalanceBefore);

        // Mint tokens to swap
        fromToken.deal(address(operator), 100e18);

        // Setup operation
        ERC20SwapOperator.ERC20SwapOperationData memory operationData = ERC20SwapOperator
            .ERC20SwapOperationData({
                fromToken: fromToken,
                toToken: toToken,
                minReceivedAmount: 95e18
            });

        ERC20SwapOperator.ERC20SwapExecutionData memory executionData = ERC20SwapOperator
            .ERC20SwapExecutionData({
                target: payable(address(aggregator)),
                callData: abi.encodeWithSelector(
                    aggregator.swap.selector,
                    fromToken,
                    toToken,
                    100e18,
                    address(this)
                ),
                isReceivedDirectly: true
            });

        // Execute operation
        vm.expectEmit(true, true, true, true);
        emit ERC20SwapOperationExecuted(
            Party(payable(address(this))),
            fromToken,
            toToken,
            100e18,
            99e18
        );
        operator.execute(abi.encode(operationData), abi.encode(executionData), address(0));

        assertEq(toToken.balanceOf(address(this)), toTokenBalanceBefore + 99e18);
        assertEq(fromToken.balanceOf(address(this)), 0);
        assertEq(toToken.balanceOf(address(operator)), 0);
        assertEq(fromToken.balanceOf(address(operator)), 0);
        assertEq(fromToken.allowance(address(operator), address(aggregator)), 0);
    }

    function test_ERC20Swap_canReceiveETH() public {
        fromToken.deal(address(operator), 100e18);

        ERC20SwapOperator.ERC20SwapOperationData memory operationData = ERC20SwapOperator
            .ERC20SwapOperationData({
                fromToken: fromToken,
                toToken: ETH_TOKEN_ADDRESS,
                minReceivedAmount: 95e18
            });

        ERC20SwapOperator.ERC20SwapExecutionData memory executionData = ERC20SwapOperator
            .ERC20SwapExecutionData({
                target: payable(address(aggregator)),
                callData: abi.encodeWithSelector(
                    aggregator.swap.selector,
                    fromToken,
                    ETH_TOKEN_ADDRESS,
                    100e18,
                    address(operator)
                ),
                isReceivedDirectly: false
            });

        uint256 balanceBefore = address(this).balance;

        // Execute operation
        vm.expectEmit(true, true, true, true);
        emit ERC20SwapOperationExecuted(
            Party(payable(address(this))),
            fromToken,
            ETH_TOKEN_ADDRESS,
            100e18,
            99e18
        );
        operator.execute(abi.encode(operationData), abi.encode(executionData), address(0));

        assertEq(fromToken.balanceOf(address(this)), 0);
        assertEq(fromToken.balanceOf(address(operator)), 0);
        assertEq(fromToken.allowance(address(operator), address(aggregator)), 0);
        assertEq(address(this).balance - balanceBefore, 99e18);
    }

    function test_ERC20Swap_canRefundLeftoverTokens() public {
        // Mint tokens to swap
        fromToken.deal(address(operator), 100e18);

        // Setup operation
        ERC20SwapOperator.ERC20SwapOperationData memory operationData = ERC20SwapOperator
            .ERC20SwapOperationData({
                fromToken: fromToken,
                toToken: toToken,
                minReceivedAmount: 45e18
            });

        ERC20SwapOperator.ERC20SwapExecutionData memory executionData = ERC20SwapOperator
            .ERC20SwapExecutionData({
                target: payable(address(aggregator)),
                callData: abi.encodeWithSelector(
                    aggregator.swap.selector,
                    fromToken,
                    toToken,
                    50e18,
                    address(operator)
                ),
                isReceivedDirectly: false
            });

        // Execute operation
        vm.expectEmit(true, true, true, true);
        emit ERC20SwapOperationExecuted(
            Party(payable(address(this))),
            fromToken,
            toToken,
            100e18,
            49.5e18
        );
        operator.execute(abi.encode(operationData), abi.encode(executionData), address(0));

        assertEq(toToken.balanceOf(address(this)), 49.5e18);
        assertEq(fromToken.balanceOf(address(this)), 50e18);
        assertEq(toToken.balanceOf(address(operator)), 0);
        assertEq(fromToken.balanceOf(address(operator)), 0);
    }

    function test_ERC20Swap_withUnauthorizedTarget() public {
        fromToken.deal(address(operator), 100e18);

        ERC20SwapOperator.ERC20SwapOperationData memory operationData = ERC20SwapOperator
            .ERC20SwapOperationData({
                fromToken: fromToken,
                toToken: toToken,
                minReceivedAmount: 95e18
            });

        address unauthorizedTarget = _randomAddress();
        ERC20SwapOperator.ERC20SwapExecutionData memory executionData = ERC20SwapOperator
            .ERC20SwapExecutionData({
                target: payable(unauthorizedTarget), // Set an unauthorized target
                callData: abi.encodeWithSelector(
                    aggregator.swap.selector,
                    fromToken,
                    toToken,
                    100e18,
                    address(operator)
                ),
                isReceivedDirectly: false
            });

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20SwapOperator.UnauthorizedTargetError.selector,
                unauthorizedTarget
            )
        );
        operator.execute(abi.encode(operationData), abi.encode(executionData), address(0));
    }

    function test_ERC20Swap_withFailingCall() public {
        fromToken.deal(address(operator), 100e18);

        ERC20SwapOperator.ERC20SwapOperationData memory operationData = ERC20SwapOperator
            .ERC20SwapOperationData({
                fromToken: fromToken,
                toToken: toToken,
                minReceivedAmount: 95e18
            });

        ERC20SwapOperator.ERC20SwapExecutionData memory executionData = ERC20SwapOperator
            .ERC20SwapExecutionData({
                target: payable(address(aggregator)),
                callData: abi.encodeWithSelector(aggregator.triggerRevert.selector), // Call a function that reverts
                isReceivedDirectly: false
            });

        vm.expectRevert("ERROR");
        operator.execute(abi.encode(operationData), abi.encode(executionData), address(0));
    }

    function test_ERC20Swap_withInsufficientReceivedAmount_withoutPreviousBalance() public {
        fromToken.deal(address(operator), 100e18);

        ERC20SwapOperator.ERC20SwapOperationData memory operationData = ERC20SwapOperator
            .ERC20SwapOperationData({
                fromToken: fromToken,
                toToken: toToken,
                minReceivedAmount: 101e18 // Set a higher minimum received amount
            });

        ERC20SwapOperator.ERC20SwapExecutionData memory executionData = ERC20SwapOperator
            .ERC20SwapExecutionData({
                target: payable(address(aggregator)),
                callData: abi.encodeWithSelector(
                    aggregator.swap.selector,
                    fromToken,
                    toToken,
                    100e18,
                    address(operator)
                ),
                isReceivedDirectly: false
            });

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20SwapOperator.InsufficientReceivedAmountError.selector,
                99e18, // Received amount
                101e18 // Minimum received amount required
            )
        );
        operator.execute(abi.encode(operationData), abi.encode(executionData), address(0));
    }

    function test_ERC20Swap_withInsufficientReceivedAmount_withPreviousBalance() public {
        uint256 toTokenBalanceBefore = _randomUint256();
        toToken.deal(address(this), toTokenBalanceBefore);

        fromToken.deal(address(operator), 100e18);

        ERC20SwapOperator.ERC20SwapOperationData memory operationData = ERC20SwapOperator
            .ERC20SwapOperationData({
                fromToken: fromToken,
                toToken: toToken,
                minReceivedAmount: 95e18
            });
        ERC20SwapOperator.ERC20SwapExecutionData memory executionData = ERC20SwapOperator
            .ERC20SwapExecutionData({
                target: payable(address(aggregator)),
                callData: abi.encodeWithSelector(
                    aggregator.swap.selector,
                    fromToken,
                    toToken,
                    95e18,
                    address(this)
                ),
                isReceivedDirectly: true
            });
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20SwapOperator.InsufficientReceivedAmountError.selector,
                (95e18 * (10000 - 100 /* aggregator slippage */)) / 10000, // Received amount
                95e18 // Minimum received amount required
            )
        );
        operator.execute(abi.encode(operationData), abi.encode(executionData), address(0));
    }

    function test_setTargetAllowed_works() public {
        address newTarget = _randomAddress();

        assertEq(operator.isTargetAllowed(newTarget), false);

        vm.expectEmit(true, true, true, true);
        emit TargetAllowedSet(newTarget, true);
        vm.prank(multisig);
        operator.setTargetAllowed(newTarget, true);

        assertEq(operator.isTargetAllowed(newTarget), true);
    }

    function test_setTargetAllowed_onlyMultisig() public {
        address newTarget = _randomAddress();

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20SwapOperator.OnlyPartyDaoError.selector,
                address(this),
                multisig
            )
        );
        operator.setTargetAllowed(newTarget, true);
    }

    function test_inKindSwapShouldRevert() public {
        // Mint tokens to swap
        fromToken.deal(address(operator), 100e18);

        // Setup operation
        ERC20SwapOperator.ERC20SwapOperationData memory operationData = ERC20SwapOperator
            .ERC20SwapOperationData({
                fromToken: fromToken,
                toToken: fromToken,
                minReceivedAmount: 95e18
            });

        ERC20SwapOperator.ERC20SwapExecutionData memory executionData = ERC20SwapOperator
            .ERC20SwapExecutionData({
                target: payable(address(aggregator)),
                callData: abi.encodeWithSelector(
                    aggregator.swap.selector,
                    fromToken,
                    fromToken,
                    100e18,
                    address(operator)
                ),
                isReceivedDirectly: false
            });

        // Execute operation
        vm.expectRevert(ERC20SwapOperator.InKindSwap.selector);
        operator.execute(abi.encode(operationData), abi.encode(executionData), address(0));
    }

    receive() external payable {}
}

contract DummyAggregator is Test {
    uint16 slippageBps = 100; // Default to 1%

    function setSlippage(uint16 newSlippageBps) external {
        slippageBps = newSlippageBps;
    }

    function swap(
        IERC20 fromToken,
        IERC20 toToken,
        uint256 amount,
        address payable recipient
    ) external payable {
        // Burn from token
        if (fromToken == ETH_TOKEN_ADDRESS) {
            payable(address(0)).transfer(amount);
        } else {
            fromToken.transferFrom(msg.sender, address(0), amount);
        }

        // Calculate amount received
        uint256 receivedAmount = amount - ((amount * slippageBps) / 10000);

        // Mint to tokens contract to recipient
        if (toToken == ETH_TOKEN_ADDRESS) {
            vm.deal(recipient, receivedAmount);
        } else {
            DummyERC20(address(toToken)).deal(recipient, receivedAmount);
        }
    }

    function triggerRevert() external pure {
        revert("ERROR");
    }

    receive() external payable {}
}
