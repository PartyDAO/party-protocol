// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { BlastClaimableYield } from "./utils/BlastClaimableYield.sol";
import { TokenDistributor, IGlobals } from "../distribution/TokenDistributor.sol";

contract TokenDistributorBlast is TokenDistributor, BlastClaimableYield {
    constructor(
        IGlobals globals,
        uint40 emergencyDisabledTimestamp,
        address blast,
        address governor
    ) TokenDistributor(globals, emergencyDisabledTimestamp) BlastClaimableYield(blast, governor) {}
}
