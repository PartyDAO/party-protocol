// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/ArbitraryCallsProposal.sol";
import "../../contracts/proposals/vendor/IOpenseaExchange.sol";

import "../proposals/OpenseaTestUtils.sol";
import "../TestUtils.sol";
import "../DummyERC721.sol";

contract TestableArbitraryCallsProposal is ArbitraryCallsProposal {
    constructor(IZoraAuctionHouse zora) ArbitraryCallsProposal(zora) {}

    function execute(
        IProposalExecutionEngine.ExecuteProposalParams calldata params
    ) external payable returns (bytes memory nextProgressData) {
        nextProgressData = _executeArbitraryCalls(params);
    }

    function approveTokenSpender(address spender, IERC721 token, uint256 tokenId) external {
        token.approve(spender, tokenId);
    }
}

contract ArbitraryCallTarget {
    using LibRawResult for bytes;

    error ArbitraryCallTargetFailError(address caller, uint256 value, bytes32 stuff);
    event ArbitraryCallTargetSuccessCalled(address caller, uint256 value, bytes32 stuff);

    function success(bytes32 stuff, bytes memory returnData) external payable {
        emit ArbitraryCallTargetSuccessCalled(msg.sender, msg.value, stuff);
        returnData.rawReturn();
    }

    function fail(bytes32 stuff) external payable {
        revert ArbitraryCallTargetFailError(msg.sender, msg.value, stuff);
    }

    function yoink(IERC721 token, uint256 tokenId) external {
        token.transferFrom(token.ownerOf(tokenId), address(this), tokenId);
    }

    function restore(address to, IERC721 token, uint256 tokenId) external {
        token.transferFrom(address(this), to, tokenId);
    }
}

contract FakeZora {
    function cancelAuction(uint256 auctionId) external {}
}

contract ArbitraryCallsProposalTest is
    Test,
    TestUtils,
    OpenseaTestUtils(IOpenseaExchange(address(0)))
{
    event ArbitraryCallTargetSuccessCalled(address caller, uint256 value, bytes32 stuff);

    event ArbitraryCallExecuted(uint256 proposalId, uint256 idx, uint256 count);

    ArbitraryCallTarget target = new ArbitraryCallTarget();
    FakeZora zora = new FakeZora();
    TestableArbitraryCallsProposal testContract =
        new TestableArbitraryCallsProposal(IZoraAuctionHouse(address(zora)));
    IERC721[] preciousTokens;
    uint256[] preciousTokenIds;

    constructor() {
        for (uint256 i; i < 2; ++i) {
            DummyERC721 t = new DummyERC721();
            preciousTokens.push(t);
            preciousTokenIds.push(t.mint(address(testContract)));
            // Approve ArbitraryCallTarget so yoink() works.
            testContract.approveTokenSpender(address(target), t, preciousTokenIds[i]);
        }
    }

    function _createTestProposal(
        ArbitraryCallsProposal.ArbitraryCall[] memory calls
    ) private view returns (IProposalExecutionEngine.ExecuteProposalParams memory executeParams) {
        executeParams = IProposalExecutionEngine.ExecuteProposalParams({
            proposalId: _randomUint256(),
            proposalData: abi.encode(calls),
            progressData: "",
            extraData: "",
            flags: 0,
            preciousTokens: preciousTokens,
            preciousTokenIds: preciousTokenIds
        });
    }

    function _pickRandomPreciousToken() private view returns (IERC721 token, uint256 tokenId) {
        uint256 idx = _randomRange(0, preciousTokens.length);
        return (preciousTokens[idx], preciousTokenIds[idx]);
    }

    function _createSimpleCalls(
        uint256 count,
        bool shouldCallsReturnData
    )
        private
        view
        returns (ArbitraryCallsProposal.ArbitraryCall[] memory calls, bytes32[] memory callArgs)
    {
        calls = new ArbitraryCallsProposal.ArbitraryCall[](count);
        callArgs = new bytes32[](count);
        bytes[] memory callResults = new bytes[](count);
        for (uint256 i; i < count; ++i) {
            callArgs[i] = _randomBytes32();
            callResults[i] = shouldCallsReturnData ? abi.encode(_randomBytes32()) : bytes("");
            calls[i] = ArbitraryCallsProposal.ArbitraryCall({
                target: payable(address(target)),
                value: 0,
                data: abi.encodeCall(ArbitraryCallTarget.success, (callArgs[i], callResults[i])),
                expectedResultHash: shouldCallsReturnData ? keccak256(callResults[i]) : bytes32(0)
            });
        }
    }

    function test_canExecuteSimpleCall() external {
        (
            ArbitraryCallsProposal.ArbitraryCall[] memory calls,
            bytes32[] memory callArgs
        ) = _createSimpleCalls(1, false);
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        for (uint256 i; i < calls.length; ++i) {
            _expectNonIndexedEmit();
            emit ArbitraryCallTargetSuccessCalled(address(testContract), 0, callArgs[i]);
            _expectNonIndexedEmit();
            emit ArbitraryCallExecuted(prop.proposalId, i, calls.length);
        }
        testContract.execute(prop);
    }

    function test_canExecuteTwoSimpleCalls() external {
        (
            ArbitraryCallsProposal.ArbitraryCall[] memory calls,
            bytes32[] memory callArgs
        ) = _createSimpleCalls(2, false);
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        for (uint256 i; i < calls.length; ++i) {
            _expectNonIndexedEmit();
            emit ArbitraryCallTargetSuccessCalled(address(testContract), 0, callArgs[i]);
            _expectNonIndexedEmit();
            emit ArbitraryCallExecuted(prop.proposalId, i, calls.length);
        }
        testContract.execute(prop);
    }

    function test_canExecuteSimpleCallWithResultCheck() external {
        (
            ArbitraryCallsProposal.ArbitraryCall[] memory calls,
            bytes32[] memory callArgs
        ) = _createSimpleCalls(1, true);
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        for (uint256 i; i < calls.length; ++i) {
            _expectNonIndexedEmit();
            emit ArbitraryCallTargetSuccessCalled(address(testContract), 0, callArgs[i]);
            _expectNonIndexedEmit();
            emit ArbitraryCallExecuted(prop.proposalId, i, calls.length);
        }
        testContract.execute(prop);
    }

    function test_failsIfResultCheckDoesNotPass() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, true);
        bytes32 actualResultHash = calls[0].expectedResultHash;
        calls[0].expectedResultHash = _randomBytes32();
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.UnexpectedCallResultHashError.selector,
                0,
                actualResultHash,
                calls[0].expectedResultHash
            )
        );
        testContract.execute(prop);
    }

    function test_canExecuteCallWithEth() external {
        (
            ArbitraryCallsProposal.ArbitraryCall[] memory calls,
            bytes32[] memory callArgs
        ) = _createSimpleCalls(1, false);
        calls[0].value = 1e18;
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        for (uint256 i; i < calls.length; ++i) {
            _expectNonIndexedEmit();
            emit ArbitraryCallTargetSuccessCalled(
                address(testContract),
                calls[i].value,
                callArgs[i]
            );
            _expectNonIndexedEmit();
            emit ArbitraryCallExecuted(prop.proposalId, i, calls.length);
        }
        testContract.execute{ value: 1e18 }(prop);
    }

    function test_canExecuteMultipleCallsWithEth() external {
        (
            ArbitraryCallsProposal.ArbitraryCall[] memory calls,
            bytes32[] memory callArgs
        ) = _createSimpleCalls(2, false);
        calls[0].value = 1e18;
        calls[1].value = 0.5e18;
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        for (uint256 i; i < calls.length; ++i) {
            _expectNonIndexedEmit();
            emit ArbitraryCallTargetSuccessCalled(
                address(testContract),
                calls[i].value,
                callArgs[i]
            );
            _expectNonIndexedEmit();
            emit ArbitraryCallExecuted(prop.proposalId, i, calls.length);
        }
        testContract.execute{ value: 1.5e18 }(prop);
    }

    function test_canExecuteCallWithEth_refundsLeftover() external {
        (
            ArbitraryCallsProposal.ArbitraryCall[] memory calls,
            bytes32[] memory callArgs
        ) = _createSimpleCalls(1, false);
        calls[0].value = 1e18;
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        for (uint256 i; i < calls.length; ++i) {
            _expectNonIndexedEmit();
            emit ArbitraryCallTargetSuccessCalled(
                address(testContract),
                calls[i].value,
                callArgs[i]
            );
            _expectNonIndexedEmit();
            emit ArbitraryCallExecuted(prop.proposalId, i, calls.length);
        }
        uint256 balanceBefore = address(this).balance;
        testContract.execute{ value: 2e18 }(prop);
        uint256 balanceAfter = address(this).balance;
        // Spent 2 ETH, refunded 1 ETH
        assertEq(balanceBefore - balanceAfter, 1e18);
    }

    function test_cannotConsumeMoreEthThanAttachedWithSingleCall() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        calls[0].value = 1e18;
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.NotEnoughEthAttachedError.selector,
                calls[0].value,
                calls[0].value - 1
            )
        );
        // Only submit enough ETH to cover one succeeding call.
        testContract.execute{ value: calls[0].value - 1 }(prop);
    }

    function test_cannotConsumeMoreEthThanAttachedWithMultipleCalls() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(2, false);
        calls[0].value = 1e18;
        calls[1].value = 0.5e18;
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.NotEnoughEthAttachedError.selector,
                calls[1].value,
                0.25e18
            )
        );
        // Only submit enough ETH to cover one succeeding call.
        testContract.execute{ value: 1.25e18 }(prop);
    }

    function test_failsIfPreciousIsLost() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        (IERC721 preciousToken, uint256 preciousTokenId) = _pickRandomPreciousToken();
        calls[0].data = abi.encodeCall(ArbitraryCallTarget.yoink, (preciousToken, preciousTokenId));
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.PreciousLostError.selector,
                preciousToken,
                preciousTokenId
            )
        );
        testContract.execute(prop);
    }

    function test_succeedsIfPreciousIsLostThenReturned() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(2, false);
        (IERC721 preciousToken, uint256 preciousTokenId) = _pickRandomPreciousToken();
        calls[0].data = abi.encodeCall(ArbitraryCallTarget.yoink, (preciousToken, preciousTokenId));
        calls[1].data = abi.encodeCall(
            ArbitraryCallTarget.restore,
            (address(testContract), preciousToken, preciousTokenId)
        );
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        testContract.execute(prop);
    }

    function test_succeedsIfPreciousIsLostButUnanimous() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        (IERC721 preciousToken, uint256 preciousTokenId) = _pickRandomPreciousToken();
        calls[0].data = abi.encodeCall(ArbitraryCallTarget.yoink, (preciousToken, preciousTokenId));
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        prop.flags |= LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        testContract.execute(prop);
        assertEq(preciousToken.ownerOf(preciousTokenId), address(target));
    }

    function test_canTransferNonPreciousToken() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        DummyERC721 token = new DummyERC721();
        uint256 tokenId = token.mint(address(testContract));
        calls[0].target = payable(address(token));
        calls[0].data = abi.encodeCall(
            DummyERC721.transferFrom,
            (address(testContract), address(1), tokenId)
        );
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        testContract.execute(prop);
        assertEq(token.ownerOf(tokenId), address(1));
    }

    function test_canTransferNonPreciousTokenId() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        (IERC721 preciousToken, ) = _pickRandomPreciousToken();
        DummyERC721 token = DummyERC721(address(preciousToken));
        uint256 tokenId = token.mint(address(testContract));
        calls[0].target = payable(address(token));
        calls[0].data = abi.encodeCall(
            DummyERC721.transferFrom,
            (address(testContract), address(1), tokenId)
        );
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        testContract.execute(prop);
        assertEq(token.ownerOf(tokenId), address(1));
    }

    function test_canCallApproveOnNonPreciousTokenId() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        (IERC721 preciousToken, ) = _pickRandomPreciousToken();
        DummyERC721 token = DummyERC721(address(preciousToken));
        uint256 tokenId = token.mint(address(testContract));
        calls[0].target = payable(address(token));
        calls[0].data = abi.encodeCall(DummyERC721.approve, (address(1), tokenId));
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        testContract.execute(prop);
        assertEq(token.getApproved(tokenId), address(1));
    }

    function test_canCallSetApprovalForAllOnNonPreciousToken() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        DummyERC721 token = new DummyERC721();
        calls[0].target = payable(address(token));
        calls[0].data = abi.encodeCall(DummyERC721.setApprovalForAll, (address(1), true));
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        testContract.execute(prop);
        assertEq(token.isApprovedForAll(address(testContract), address(1)), true);
    }

    function test_cannotCallSetApprovalForAllOnPreciousToken() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        (IERC721 preciousToken, ) = _pickRandomPreciousToken();
        calls[0].target = payable(address(preciousToken));
        calls[0].data = abi.encodeCall(DummyERC721.setApprovalForAll, (address(1), true));
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.CallProhibitedError.selector,
                calls[0].target,
                calls[0].data
            )
        );
        testContract.execute(prop);
        assertEq(preciousToken.isApprovedForAll(address(testContract), address(1)), false);
    }

    function test_cannotCallApproveOnPreciousTokenId() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        (IERC721 preciousToken, uint256 preciousTokenId) = _pickRandomPreciousToken();
        calls[0].target = payable(address(preciousToken));
        calls[0].data = abi.encodeCall(DummyERC721.approve, (address(1), preciousTokenId));
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.CallProhibitedError.selector,
                calls[0].target,
                calls[0].data
            )
        );
        testContract.execute(prop);
    }

    function test_canCallApproveOnPreciousTokenIfDisabling() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        (IERC721 preciousToken, uint256 preciousTokenId) = _pickRandomPreciousToken();
        calls[0].target = payable(address(preciousToken));
        calls[0].data = abi.encodeCall(DummyERC721.approve, (address(0), preciousTokenId));
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        testContract.execute(prop);
        assertEq(preciousToken.getApproved(preciousTokenId), address(0));
    }

    function test_canCallSetApprovalForAllOnPreciousTokenIfDisabling() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        (IERC721 preciousToken, ) = _pickRandomPreciousToken();
        calls[0].target = payable(address(preciousToken));
        calls[0].data = abi.encodeCall(DummyERC721.setApprovalForAll, (address(1), false));
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        testContract.execute(prop);
        assertEq(preciousToken.isApprovedForAll(address(testContract), address(1)), false);
    }

    function test_canCallApproveOnPreciousTokenIfUnanimous() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        (IERC721 preciousToken, uint256 preciousTokenId) = _pickRandomPreciousToken();
        calls[0].target = payable(address(preciousToken));
        calls[0].data = abi.encodeCall(DummyERC721.approve, (address(1), preciousTokenId));
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        prop.flags |= LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        testContract.execute(prop);
        assertEq(preciousToken.getApproved(preciousTokenId), address(1));
    }

    function test_canCallSetApprovalForAllOnPreciousTokenIfUnanimous() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        (IERC721 preciousToken, ) = _pickRandomPreciousToken();
        calls[0].target = payable(address(preciousToken));
        calls[0].data = abi.encodeCall(DummyERC721.setApprovalForAll, (address(1), true));
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        prop.flags |= LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        testContract.execute(prop);
        assertEq(preciousToken.isApprovedForAll(address(testContract), address(1)), true);
    }

    function test_cannotCallOnERC721Received() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        calls[0].target = _randomAddress();
        calls[0].data = abi.encodeCall(
            IERC721Receiver.onERC721Received,
            (_randomAddress(), _randomAddress(), _randomUint256(), bytes(""))
        );
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.CallProhibitedError.selector,
                calls[0].target,
                calls[0].data
            )
        );
        testContract.execute(prop);
    }

    function test_cannotCallOnERC1155Received() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        calls[0].target = _randomAddress();
        calls[0].data = abi.encodeCall(
            ERC1155TokenReceiverBase.onERC1155Received,
            (_randomAddress(), _randomAddress(), _randomUint256(), _randomUint256(), bytes(""))
        );
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.CallProhibitedError.selector,
                calls[0].target,
                calls[0].data
            )
        );
        testContract.execute(prop);
    }

    function test_cannotCallOnERC1155BatchReceived() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        calls[0].target = _randomAddress();
        calls[0].data = abi.encodeCall(
            ERC1155TokenReceiverBase.onERC1155BatchReceived,
            (_randomAddress(), _randomAddress(), _toUint256Array(0), _toUint256Array(0), bytes(""))
        );
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.CallProhibitedError.selector,
                calls[0].target,
                calls[0].data
            )
        );
        testContract.execute(prop);
    }

    function test_cannotCallValidateOnOpensea() external {
        IOpenseaExchange.Order[] memory orders = new IOpenseaExchange.Order[](1);
        orders[0] = _createFullOpenseaOrderParams(
            BuyOpenseaListingParams({
                // The data doesn't matter, it should be reverted.
                maker: payable(address(0)),
                buyer: address(0),
                tokenType: ListOnOpenseaAdvancedProposal.TokenType.ERC721,
                token: address(0),
                tokenId: 0,
                listPrice: 0,
                startTime: 0,
                duration: 0,
                zone: address(0),
                conduitKey: bytes32(0)
            })
        );
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        calls[0].target = _randomAddress();
        calls[0].data = abi.encodeCall(IOpenseaExchange.validate, (orders));
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.CallProhibitedError.selector,
                calls[0].target,
                calls[0].data
            )
        );
        testContract.execute(prop);
    }

    function test_cannotCallCancelAuctionOnZoraIfNotLastCall() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(2, false);
        calls[0].target = payable(address(zora));
        calls[0].data = abi.encodeCall(
            IZoraAuctionHouse.cancelAuction,
            (_randomUint256()) // params don't matter
        );
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.CallProhibitedError.selector,
                calls[0].target,
                calls[0].data
            )
        );
        testContract.execute(prop);
    }

    function test_canCallCancelAuctionOnZoraIfLastCall() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(2, false);
        calls[1].target = payable(address(zora));
        calls[1].data = abi.encodeCall(
            IZoraAuctionHouse.cancelAuction,
            (_randomUint256()) // params don't matter
        );
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        _expectEmit0();
        emit ArbitraryCallExecuted(prop.proposalId, 0, 2);
        _expectEmit0();
        emit ArbitraryCallExecuted(prop.proposalId, 1, 2);
        testContract.execute(prop);
    }

    function test_cannotExecuteShortApproveCallData() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        calls[0].target = _randomAddress();
        calls[0].data = abi.encodeCall(IERC721.approve, (address(0), _randomUint256()));
        _truncate(calls[0].data, 1);
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.InvalidApprovalCallLength.selector,
                calls[0].data.length
            )
        );
        testContract.execute(prop);
    }

    function test_cannotExecuteShortSetApprovalForAllCallData() external {
        (ArbitraryCallsProposal.ArbitraryCall[] memory calls, ) = _createSimpleCalls(1, false);
        calls[0].target = _randomAddress();
        calls[0].data = abi.encodeCall(IERC721.setApprovalForAll, (_randomAddress(), false));
        _truncate(calls[0].data, 1);
        IProposalExecutionEngine.ExecuteProposalParams memory prop = _createTestProposal(calls);
        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.InvalidApprovalCallLength.selector,
                calls[0].data.length
            )
        );
        testContract.execute(prop);
    }

    function _truncate(bytes memory data, uint256 bytesFromEnd) private pure {
        require(data.length >= bytesFromEnd, "data too short");
        assembly {
            mstore(data, sub(mload(data), bytesFromEnd))
        }
    }

    // To receive ETH refunds
    receive() external payable {}
}
