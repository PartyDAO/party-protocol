// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

// Interface for a gatekeeper contract used for private crowdfund instances.
interface IGateKeeper {
    function isAllowed(
        // Contributor address.
        address participant,
        // ID determined by the gatekeeper impl to identify the specific
        // strategy. The CF contract will always pass in the same ID for its
        // lifecycle.
        bytes12 id,
        // Optional arbitrary data the contributor to a CF can pass in
        // to verify proof of membership.
        bytes memory userData
    ) external view returns (bool);
}
