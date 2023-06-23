// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

// Interface for a gatekeeper contract used for private crowdfund instances.
interface IGateKeeper {
    /// @notice Check if a participant is eligible to participate in a crowdfund.
    /// @param participant The address of the participant.
    /// @param id The ID of the gate to eligibility against.
    /// @param userData The data used to check eligibility.
    /// @return `true` if the participant is allowed to participate, `false` otherwise.
    function isAllowed(
        address participant,
        bytes12 id,
        bytes memory userData
    ) external view returns (bool);
}
