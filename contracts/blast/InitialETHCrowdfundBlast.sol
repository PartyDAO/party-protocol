// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { IBlast, YieldMode, GasMode } from "./utils/IBlast.sol";
import { InitialETHCrowdfund, MetadataProvider, IGlobals } from "../crowdfund/InitialETHCrowdfund.sol";
import { MetadataProvider } from "../renderers/MetadataProvider.sol";

contract InitialETHCrowdfundBlast is InitialETHCrowdfund {
    IBlast immutable BLAST;
    constructor(IGlobals globals, address blast) InitialETHCrowdfund(globals) {
        BLAST = IBlast(blast);
    }

    function initialize(
        InitialETHCrowdfund.InitialETHCrowdfundOptions memory crowdfundOpts,
        InitialETHCrowdfund.ETHPartyOptions memory partyOpts,
        MetadataProvider customMetadataProvider,
        bytes memory customMetadata
    ) public payable override {
        super.initialize(crowdfundOpts, partyOpts, customMetadataProvider, customMetadata);
        BLAST.configure(YieldMode.AUTOMATIC, GasMode.CLAIMABLE, address(party));
    }
}
