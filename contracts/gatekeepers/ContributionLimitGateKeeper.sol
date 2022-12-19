// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../crowdfund/Crowdfund.sol";
import "./IGateKeeper.sol";

/// @notice A gateKeeper that limits the total amount that can be contributed per address.
contract ContributionLimitGateKeeper is IGateKeeper {
    uint96 private _lastId;

    struct ContributionLimit {
        uint96 min;
        uint96 max;
    }

    /// @notice Get the merkle root used by a gate identifyied by it's `id`.
    mapping(uint96 => ContributionLimit) public contributionLimits;

    /// @inheritdoc IGateKeeper
    function isAllowed(
        address participant,
        bytes12 id,
        bytes memory userData
    ) external view returns (bool) {
        uint96 amount = abi.decode(userData, (uint96));
        ContributionLimit memory limits = contributionLimits[uint96(id)];
        (uint256 ethContributed, , , ) = Crowdfund(msg.sender).getContributorInfo(participant);
        return amount >= limits.min && ethContributed + amount <= limits.max;
    }

    /// @notice Create a new gate that limits the total amounts that can be contributed.
    /// @param minContributed The minimum amount that can be contributed per contributor.
    /// @param maxContributed The maximum amount that can be contributed per contributor.
    /// @return id The ID of the new gate.
    function createGate(
        uint96 minContributed,
        uint96 maxContributed
    ) external returns (bytes12 id) {
        uint96 id_ = ++_lastId;
        contributionLimits[id_] = ContributionLimit({ min: minContributed, max: maxContributed });
        id = bytes12(id_);
    }
}
