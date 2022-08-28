// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./TestableSetPreciousListProposal.sol";
import "../DummyERC721.sol";
import "../TestUtils.sol";

contract SetPreciousListProposalTest is TestUtils {
    TestableSetPreciousListProposal impl = new TestableSetPreciousListProposal();
    IERC721[] preciousTokens;
    uint256[] preciousTokenIds;

    constructor() {
        _addPreciousTokens(address(impl), 3);
        impl.setPreciousList(preciousTokens, preciousTokenIds);
    }

    function _addPreciousTokens(address owner, uint256 count)
        private
        returns (IERC721[] memory tokens, uint256[] memory tokenIds)
    {
        tokens = new IERC721[](count);
        tokenIds = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            DummyERC721 t = new DummyERC721();
            uint256 tid = t.mint(owner);

            tokens[i] = t;
            tokenIds[i] = tid;
            preciousTokens.push(t);
            preciousTokenIds.push(tid);
        }
    }

    function _shufflePreciousList() internal {
        if (preciousTokens.length < 2) return;

        for (uint256 i; i < preciousTokens.length - 1; i++) {
            uint256 index1;
            uint256 index2;
            while (index1 == index2) {
                index1 = _randomRange(0, preciousTokens.length);
                index2 = _randomRange(0, preciousTokens.length);
            }

            (preciousTokens[index1], preciousTokens[index2]) =
                (preciousTokens[index2], preciousTokens[index1]);
            (preciousTokenIds[index1], preciousTokenIds[index2]) =
                (preciousTokenIds[index2], preciousTokenIds[index1]);
        }
    }

    function _createTestProposal(
        IERC721[] memory oldPreciousTokens,
        uint256[] memory oldPreciousTokenIds,
        IERC721[] memory newPreciousTokens,
        uint256[] memory newPreciousTokenIds
    )
        private
        view
        returns (
            SetPreciousListProposal.SetPreciousListProposalData
                memory proposalData,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        )
    {
        proposalData = SetPreciousListProposal.SetPreciousListProposalData({
            newPreciousTokens: newPreciousTokens,
            newPreciousTokenIds: newPreciousTokenIds
        });

        params = IProposalExecutionEngine.ExecuteProposalParams({
            proposalId: _randomUint256(),
            proposalData: abi.encode(proposalData),
            progressData: "",
            flags: 0,
            preciousTokens: oldPreciousTokens,
            preciousTokenIds: oldPreciousTokenIds
        });
    }

    function testSetPreciousList_samePreciouses() external {
        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        ) = _createTestProposal(
                preciousTokens,
                preciousTokenIds,
                preciousTokens,
                preciousTokenIds
            );

        impl.executeSetPreciousList(params);

        assertTrue(impl.isPreciousListCorrect(preciousTokens, preciousTokenIds));
    }

    function testSetPreciousList_samePreciouses_differentOrder() external {
        IERC721[] memory oldPreciousTokens = preciousTokens;
        uint256[] memory oldPreciousTokenIds = preciousTokenIds;

        _shufflePreciousList();

        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        ) = _createTestProposal(
                oldPreciousTokens,
                oldPreciousTokenIds,
                preciousTokens,
                preciousTokenIds
            );

        impl.executeSetPreciousList(params);

        assertTrue(impl.isPreciousListCorrect(preciousTokens, preciousTokenIds));
    }

    function testSetPreciousList_addPreciouses() external {
        IERC721[] memory oldPreciousTokens = preciousTokens;
        uint256[] memory oldPreciousTokenIds = preciousTokenIds;

        _addPreciousTokens(address(impl), 2);

        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        ) = _createTestProposal(
                oldPreciousTokens,
                oldPreciousTokenIds,
                preciousTokens,
                preciousTokenIds
            );

        impl.executeSetPreciousList(params);

        assertTrue(impl.isPreciousListCorrect(preciousTokens, preciousTokenIds));
    }

    function testSetPreciousList_addPreciouses_differentOrder() external {
        IERC721[] memory oldPreciousTokens = preciousTokens;
        uint256[] memory oldPreciousTokenIds = preciousTokenIds;

        _addPreciousTokens(address(impl), 2);

        _shufflePreciousList();

        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        ) = _createTestProposal(
                oldPreciousTokens,
                oldPreciousTokenIds,
                preciousTokens,
                preciousTokenIds
            );

        impl.executeSetPreciousList(params);

        assertTrue(impl.isPreciousListCorrect(preciousTokens, preciousTokenIds));
    }

    function testSetPreciousList_removePreciouses() external {
        IERC721[] memory oldPreciousTokens = preciousTokens;
        uint256[] memory oldPreciousTokenIds = preciousTokenIds;

        // Remove an old precious from the list and from the party.
        IERC721 lastPreciousToken = preciousTokens[preciousTokens.length - 1];
        uint256 lastPreciousTokenId = preciousTokenIds[preciousTokenIds.length - 1];
        DummyERC721(address(lastPreciousToken)).burn(lastPreciousTokenId);

        preciousTokens.pop();
        preciousTokenIds.pop();

        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        ) = _createTestProposal(
                oldPreciousTokens,
                oldPreciousTokenIds,
                preciousTokens,
                preciousTokenIds
            );

        impl.executeSetPreciousList(params);

        assertTrue(impl.isPreciousListCorrect(preciousTokens, preciousTokenIds));
    }

    function testSetPreciousList_removePreciouses_differentOrder() external {
        IERC721[] memory oldPreciousTokens = preciousTokens;
        uint256[] memory oldPreciousTokenIds = preciousTokenIds;

        // Remove an old precious from the list and from the party.
        IERC721 lastPreciousToken = preciousTokens[preciousTokens.length - 1];
        uint256 lastPreciousTokenId = preciousTokenIds[preciousTokenIds.length - 1];
        DummyERC721(address(lastPreciousToken)).burn(lastPreciousTokenId);

        preciousTokens.pop();
        preciousTokenIds.pop();

        _shufflePreciousList();

        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        ) = _createTestProposal(
                oldPreciousTokens,
                oldPreciousTokenIds,
                preciousTokens,
                preciousTokenIds
            );

        impl.executeSetPreciousList(params);

        assertTrue(impl.isPreciousListCorrect(preciousTokens, preciousTokenIds));
    }

    function testSetPreciousList_removePreciouses_revertIfMissingHeldPrecious()
        external
    {
        IERC721[] memory oldPreciousTokens = preciousTokens;
        uint256[] memory oldPreciousTokenIds = preciousTokenIds;

        // Remove an old precious from the list but not from party.
        IERC721 lastPreciousToken = preciousTokens[preciousTokens.length - 1];
        uint256 lastPreciousTokenId = preciousTokenIds[preciousTokenIds.length - 1];

        preciousTokens.pop();
        preciousTokenIds.pop();

        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        ) = _createTestProposal(
                oldPreciousTokens,
                oldPreciousTokenIds,
                preciousTokens,
                preciousTokenIds
            );

        vm.expectRevert(
            abi.encodeWithSelector(
                SetPreciousListProposal.MissingPrecious.selector,
                lastPreciousToken,
                lastPreciousTokenId
            )
        );
        impl.executeSetPreciousList(params);
    }
}
