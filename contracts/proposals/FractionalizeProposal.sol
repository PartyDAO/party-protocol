// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./IProposalExecutionEngine.sol";

// Implements Fractionalize proposals.
contract FractionalizeProposal {

    function _executeFractionalize(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    )
        internal
        returns (bytes memory nextProgressData)
    {
        // TODO
        revert('unimplemented');
    }
}
