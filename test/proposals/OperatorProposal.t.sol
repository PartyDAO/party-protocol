// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/OperatorProposal.sol";

import "../TestUtils.sol";

contract TestableOperatorProposal is OperatorProposal {
    function execute(
        IProposalExecutionEngine.ExecuteProposalParams calldata params,
        bool allowOperatorsToSpendPartyEth
    ) external payable returns (bytes memory nextProgressData) {
        nextProgressData = _executeOperation(params, allowOperatorsToSpendPartyEth);
    }
}

contract MockOperator is IOperator {
    event OperationExecuted(address caller, bytes data, bytes executionData);

    function execute(
        bytes calldata data,
        bytes calldata executionData,
        address,
        bool
    ) external payable override {
        emit OperationExecuted(msg.sender, data, executionData);
    }
}

contract OperatorProposalTest is Test, TestUtils {
    event OperationExecuted(address caller, bytes data, bytes executionData);

    TestableOperatorProposal operatorProposal;
    MockOperator mockOperator;

    constructor() {
        operatorProposal = new TestableOperatorProposal();
        mockOperator = new MockOperator();
    }

    function test_executeOperation() public {
        // Prepare the operator proposal data.
        address[] memory allowedExecutors = new address[](1);
        allowedExecutors[0] = address(this);

        OperatorProposal.OperatorProposalData memory data = OperatorProposal.OperatorProposalData({
            allowedExecutors: allowedExecutors,
            operator: IOperator(address(mockOperator)),
            operatorValue: 0,
            operatorData: "0x1234"
        });

        // Execute the proposal.
        vm.expectEmit(false, false, false, true);
        emit OperationExecuted(address(operatorProposal), "0x1234", "0x5678");
        bytes memory nextProgressData = operatorProposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: abi.encode(uint256(0), "0x5678"),
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            }),
            true
        );
        assertEq(nextProgressData.length, 0);
    }

    function test_executeOperation_onlyAllowedExecutor() public {
        // Prepare the operator proposal data.
        address[] memory allowedExecutors = new address[](1);
        allowedExecutors[0] = address(this);

        OperatorProposal.OperatorProposalData memory data = OperatorProposal.OperatorProposalData({
            allowedExecutors: allowedExecutors,
            operator: IOperator(address(mockOperator)),
            operatorValue: 0,
            operatorData: "0x1234"
        });

        // Execute the proposal.
        address notAllowedExecutor = _randomAddress();
        vm.prank(notAllowedExecutor);
        vm.expectRevert(
            abi.encodeWithSelector(
                OperatorProposal.NotAllowedToExecute.selector,
                notAllowedExecutor,
                allowedExecutors
            )
        );
        bytes memory nextProgressData = operatorProposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: abi.encode(uint256(0), "0x5678"),
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            }),
            true
        );
        assertEq(nextProgressData.length, 0);
    }

    function test_executeOperation_canOnlyUseAttachedEthIfNotAllowedToSpendPartyEth() public {
        // Prepare the operator proposal data.
        address[] memory allowedExecutors = new address[](1);
        allowedExecutors[0] = address(this);

        OperatorProposal.OperatorProposalData memory data = OperatorProposal.OperatorProposalData({
            allowedExecutors: allowedExecutors,
            operator: IOperator(address(mockOperator)),
            operatorValue: 2,
            operatorData: "0x1234"
        });

        // Execute the proposal.
        vm.expectRevert(abi.encodeWithSelector(OperatorProposal.NotEnoughEthError.selector, 2, 1));
        operatorProposal.execute{ value: 1 }(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: abi.encode(uint256(0), "0x5678"),
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            }),
            false
        );
    }
}
