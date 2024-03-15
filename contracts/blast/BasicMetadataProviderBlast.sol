// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { BlastClaimableYield } from "./utils/BlastClaimableYield.sol";
import { BasicMetadataProvider, IGlobals } from "../renderers/BasicMetadataProvider.sol";

contract BasicMetadataProviderBlast is BasicMetadataProvider, BlastClaimableYield {
    constructor(
        IGlobals globals,
        address blast,
        address governor
    ) BasicMetadataProvider(globals) BlastClaimableYield(blast, governor) {}
}
