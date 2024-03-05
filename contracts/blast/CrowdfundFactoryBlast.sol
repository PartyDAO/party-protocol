// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { BlastClaimableYield } from "./utils/BlastClaimableYield.sol";
import { CrowdfundFactory } from "../crowdfund/CrowdfundFactory.sol";

contract CrowdfundFactoryBlast is CrowdfundFactory, BlastClaimableYield {
    constructor(address blast, address governor) BlastClaimableYield(blast, governor) {}
}
