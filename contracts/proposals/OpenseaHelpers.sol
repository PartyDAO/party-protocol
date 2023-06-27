// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./ListOnOpenseaAdvancedProposal.sol";
import "./IProposalExecutionEngine.sol";

// Abstract Opensea interaction functions.
abstract contract OpenseaHelpers {
    function _executeAdvancedOpenseaProposal(
        IProposalExecutionEngine.ExecuteProposalParams memory params,
        ListOnOpenseaAdvancedProposal.OpenseaAdvancedProposalData memory data
    ) internal virtual returns (bytes memory nextProgressData);
}
