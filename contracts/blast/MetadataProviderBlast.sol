// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { BlastClaimableYield } from "./utils/BlastClaimableYield.sol";
import { MetadataProvider, IGlobals } from "../renderers/MetadataProvider.sol";

contract MetadataProviderBlast is MetadataProvider, BlastClaimableYield {
    constructor(
        IGlobals globals,
        address blast,
        address governor
    ) MetadataProvider(globals) BlastClaimableYield(blast, governor) {}
}
