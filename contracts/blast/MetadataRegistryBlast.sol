// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { BlastClaimableYield } from "./utils/BlastClaimableYield.sol";
import { MetadataRegistry, IGlobals } from "../renderers/MetadataRegistry.sol";

contract MetadataRegistryBlast is MetadataRegistry, BlastClaimableYield {
    constructor(
        IGlobals globals,
        address[] memory registrars,
        address blast,
        address governor
    ) MetadataRegistry(globals, registrars) BlastClaimableYield(blast, governor) {}
}
