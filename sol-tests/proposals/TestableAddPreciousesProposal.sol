// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../../contracts/proposals/AddPreciousesProposal.sol";

contract TestableAddPreciousesProposal is AddPreciousesProposal {
    function executeAddPreciouses(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) external returns (bytes memory nextProgressData) {
        return _executeAddPreciouses(params);
    }

    function setPreciousList(
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) external {
        _setPreciousList(preciousTokens, preciousTokenIds);
    }

    function hashPreciousList(
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        external
        pure
        returns (bytes32 h)
    {
        return _hashPreciousList(preciousTokens, preciousTokenIds);
    }

    function isPreciousListCorrect(
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        external
        view
        returns (bool)
    {
        return _isPreciousListCorrect(preciousTokens, preciousTokenIds);
    }
}