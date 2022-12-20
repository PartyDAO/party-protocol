// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./IGateKeeper.sol";

/// @notice A gateKeeper that limits the amount that can be contributed per contribution.
contract ContributionRangeGateKeeper is IGateKeeper {
    uint96 private _lastId;

    error MinGreaterThanMaxError(uint96 min, uint96 max);

    struct ContributionRange {
        uint96 min;
        uint96 max;
    }

    /// @notice Get the merkle root used by a gate identifyied by it's `id`.
    mapping(uint96 => ContributionRange) public contributionRanges;

    /// @inheritdoc IGateKeeper
    function isAllowed(
        address,
        uint96 amount,
        bytes12 id,
        bytes memory
    ) external view returns (bool) {
        ContributionRange memory ranges = contributionRanges[uint96(id)];
        return amount >= ranges.min && amount <= ranges.max;
    }

    /// @notice Create a new gate that limits the amount per contribution.
    /// @param minAmount The minimum amount that can be contributed at a time.
    /// @param maxAmount The maximum amount that can be contributed at a time.
    /// @return id The ID of the new gate.
    function createGate(uint96 minAmount, uint96 maxAmount) external returns (bytes12 id) {
        if (minAmount > maxAmount) revert MinGreaterThanMaxError(minAmount, maxAmount);
        uint96 id_ = ++_lastId;
        contributionRanges[id_] = ContributionRange({ min: minAmount, max: maxAmount });
        id = bytes12(id_);
    }
}
