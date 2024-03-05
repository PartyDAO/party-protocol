// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { BlastClaimableYield } from "./utils/BlastClaimableYield.sol";
import { BondingCurveAuthority } from "../authorities/BondingCurveAuthority.sol";

contract BondingCurveAuthorityBlast is BondingCurveAuthority, BlastClaimableYield {
    constructor(
        address payable partyDao,
        uint16 initialPartyDaoFeeBps,
        uint16 initialTreasuryFeeBps,
        uint16 initialCreatorFeeBps,
        address blast,
        address governor
    )
        BondingCurveAuthority(
            partyDao,
            initialPartyDaoFeeBps,
            initialTreasuryFeeBps,
            initialCreatorFeeBps
        )
        BlastClaimableYield(blast, governor)
    {}
}
