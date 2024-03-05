// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { IBlast, YieldMode, GasMode } from "./utils/IBlast.sol";
import { Party, IGlobals } from "../party/Party.sol";

contract BlastParty is Party {
    IBlast immutable BLAST;

    constructor(IGlobals globals, address blast) Party(globals) {
        BLAST = IBlast(blast);
    }

    function initialize(PartyInitData memory initData) public override onlyInitialize {
        super.initialize(initData);
        BLAST.configure(YieldMode.AUTOMATIC, GasMode.CLAIMABLE, address(this));
    }
}
