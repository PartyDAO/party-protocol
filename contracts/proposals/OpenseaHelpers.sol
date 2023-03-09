// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./ListOnOpenseaAdvancedProposal.sol";
import "./IProposalExecutionEngine.sol";
import "./vendor/IOpenseaExchange.sol";

// Abstract Opensea interaction functions.
abstract contract OpenseaHelpers {
    function _executeAdvancedOpenseaProposal(
        IProposalExecutionEngine.ExecuteProposalParams memory params,
        ListOnOpenseaAdvancedProposal.OpenseaAdvancedProposalData memory data
    ) internal virtual returns (bytes memory nextProgressData);
}
