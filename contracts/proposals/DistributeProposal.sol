// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../party/Party.sol";
import "../distribution/ITokenDistributor.sol";
import "./IProposalExecutionEngine.sol";

// Implements proposal to create a distribution.
abstract contract DistributeProposal {
    struct DistributeProposalData {
        uint256 amount;
        ITokenDistributor.TokenType tokenType;
        address token;
        uint256 tokenId;
    }

    function _executeDistribute(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal returns (bytes memory nextProgressData) {
        // Decode the proposal data.
        DistributeProposalData memory data = abi.decode(
            params.proposalData,
            (DistributeProposalData)
        );

        // Create a distribution.
        PartyGovernance(address(this)).distribute(
            data.amount,
            data.tokenType,
            data.token,
            data.tokenId
        );

        // Nothing left to do.
        return "";
    }
}
