// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { BlastClaimableYield } from "./utils/BlastClaimableYield.sol";
import { AtomicManualParty, IPartyFactory } from "../crowdfund/AtomicManualParty.sol";

contract AtomicManualPartyBlast is AtomicManualParty, BlastClaimableYield {
    constructor(
        IPartyFactory partyFactory,
        address blast,
        address governor
    ) AtomicManualParty(partyFactory) BlastClaimableYield(blast, governor) {}
}
