// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./IGateKeeper.sol";

/// @notice A gateKeeper that limits the amount that can be contributed per contribution.
contract ContributionIncrementGateKeeper is IGateKeeper {
    uint96 private _lastId;

    struct ContributionIncrement {
        uint96 min;
        uint96 max;
    }

    /// @notice Get the merkle root used by a gate identifyied by it's `id`.
    mapping(uint96 => ContributionIncrement) public contributionLimits;

    /// @inheritdoc IGateKeeper
    function isAllowed(address, bytes12 id, bytes memory userData) external view returns (bool) {
        uint96 amount = abi.decode(userData, (uint96));
        ContributionIncrement memory increments = contributionLimits[uint96(id)];
        return amount >= increments.min && amount <= increments.max;
    }

    /// @notice Create a new gate that limits the amount per contribution.
    /// @param minAmount The minimum amount that can be contributed at a time.
    /// @param maxAmount The maximum amount that can be contributed at a time.
    /// @return id The ID of the new gate.
    function createGate(uint96 minAmount, uint96 maxAmount) external returns (bytes12 id) {
        uint96 id_ = ++_lastId;
        contributionLimits[id_] = ContributionIncrement({ min: minAmount, max: maxAmount });
        id = bytes12(id_);
    }
}
