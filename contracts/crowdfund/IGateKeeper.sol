// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Interface for a gatekeeper contract used for private crowdfund instances.
interface IGateKeeper {
    // `data` is any arbitrary bytes12 data needed by the gatekeeper implementation.
    function isAllowed(address participant, bytes12 data) external view returns (bool);
}
