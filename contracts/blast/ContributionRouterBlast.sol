// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { BlastClaimableYield } from "./utils/BlastClaimableYield.sol";
import { ContributionRouter } from "../crowdfund/ContributionRouter.sol";

contract ContributionRouterBlast is ContributionRouter, BlastClaimableYield {
    constructor(
        address owner,
        uint96 initialFeePerMint,
        address blast,
        address governor
    ) ContributionRouter(owner, initialFeePerMint) BlastClaimableYield(blast, governor) {}
}
