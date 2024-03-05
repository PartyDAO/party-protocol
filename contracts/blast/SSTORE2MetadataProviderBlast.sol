// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { BlastClaimableYield } from "./utils/BlastClaimableYield.sol";
import { SSTORE2MetadataProvider, IGlobals } from "../renderers/SSTORE2MetadataProvider.sol";

contract SSTORE2MetadataProviderBlast is SSTORE2MetadataProvider, BlastClaimableYield {
    constructor(
        IGlobals globals,
        address blast,
        address governor
    ) SSTORE2MetadataProvider(globals) BlastClaimableYield(blast, governor) {}
}
