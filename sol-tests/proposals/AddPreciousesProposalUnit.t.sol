// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./TestableAddPreciousesProposal.sol";
import "../DummyERC721.sol";
import "../TestUtils.sol";

contract AddPreciousesProposalTest is TestUtils {
    TestableAddPreciousesProposal impl = new TestableAddPreciousesProposal();
    IERC721[] preciousTokens;
    uint256[] preciousTokenIds;

    constructor() {
        (preciousTokens, preciousTokenIds) = _createPreciousTokens(
            address(this),
            2
        );
        impl.setPreciousList(preciousTokens, preciousTokenIds);
    }

    function _createPreciousTokens(address owner, uint256 count)
        private
        returns (IERC721[] memory tokens, uint256[] memory tokenIds)
    {
        tokens = new IERC721[](count);
        tokenIds = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            DummyERC721 t = new DummyERC721();
            tokens[i] = t;
            tokenIds[i] = t.mint(owner);
        }
    }

    function _addPreciousTokens(
        address owner,
        uint256 count,
        bool transfer
    )
        internal
        returns (IERC721[] memory newTokens, uint256[] memory newTokenIds)
    {
        (newTokens, newTokenIds) = _createPreciousTokens(owner, count);

        for (uint256 i; i < newTokens.length; i++) {
            preciousTokens.push(newTokens[i]);
            preciousTokenIds.push(newTokenIds[i]);

            if (transfer) {
                vm.prank(owner);
                newTokens[i].transferFrom(owner, address(impl), newTokenIds[i]);
            }
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
            AddPreciousesProposal.AddPreciousesProposalData memory proposalData,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        )
    {
        proposalData = AddPreciousesProposal.AddPreciousesProposalData({
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

    function testAddPreciouses() external {
        IERC721[] memory oldPreciousTokens = preciousTokens;
        uint256[] memory oldPreciousTokenIds = preciousTokenIds;

        _addPreciousTokens(address(this), 2, true);

        (
            ,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        ) = _createTestProposal(
                oldPreciousTokens,
                oldPreciousTokenIds,
                preciousTokens,
                preciousTokenIds
            );

        impl.executeAddPreciouses(params);

        assertTrue(
            impl.isPreciousListCorrect(preciousTokens, preciousTokenIds)
        );
    }

    function testAddPreciouses_revertIfMissingOldPrecious() external {
        IERC721[] memory oldPreciousTokens = preciousTokens;
        uint256[] memory oldPreciousTokenIds = preciousTokenIds;

        // Remove an old precious from the list.
        preciousTokens.pop();
        preciousTokenIds.pop();

        _addPreciousTokens(address(this), 2, true);

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
                AddPreciousesProposal.MissingPrecious.selector,
                oldPreciousTokens[oldPreciousTokens.length - 1],
                oldPreciousTokenIds[oldPreciousTokenIds.length - 1]
            )
        );
        impl.executeAddPreciouses(params);
    }

    function testAddPreciouses_revertIfNewPreciousNotReceived() external {
        IERC721[] memory oldPreciousTokens = preciousTokens;
        uint256[] memory oldPreciousTokenIds = preciousTokenIds;

        _addPreciousTokens(address(this), 2, false);

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
                AddPreciousesProposal.PreciousNotReceived.selector,
                preciousTokens[2],
                preciousTokenIds[2]
            )
        );
        impl.executeAddPreciouses(params);
    }
}
