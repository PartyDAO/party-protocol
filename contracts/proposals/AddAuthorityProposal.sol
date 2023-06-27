// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../party/Party.sol";
import "../utils/LibRawResult.sol";
import "./IProposalExecutionEngine.sol";

/// @notice A proposal to add an authority to the party.
abstract contract AddAuthorityProposal {
    using LibRawResult for bytes;

    struct AddAuthorityProposalData {
        address target;
        bytes callData;
    }

    function _executeAddAuthority(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal returns (bytes memory nextProgressData) {
        // Decode the proposal data.
        AddAuthorityProposalData memory data = abi.decode(
            params.proposalData,
            (AddAuthorityProposalData)
        );

        address authority;
        if (data.callData.length == 0) {
            // Use the target as the authority if no call data is provided.
            authority = data.target;
        } else {
            // Call the target with the provided call data.
            (bool success, bytes memory response) = data.target.call(data.callData);

            if (!success) {
                response.rawRevert();
            }

            // Decode the response as the authority to add.
            (authority) = abi.decode(response, (address));
        }

        // Add the crowdfund as an authority on the party.
        Party(payable(address(this))).addAuthority(authority);

        // Nothing left to do.
        return "";
    }
}
