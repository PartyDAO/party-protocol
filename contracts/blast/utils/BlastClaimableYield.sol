// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { IBlast, YieldMode, GasMode } from "./IBlast.sol";

abstract contract BlastClaimableYield {
    /// @notice Constructor to configure the contract with Blast.
    constructor(address blast, address governor) {
        bytes memory blastCalldata = abi.encodeCall(
            IBlast.configure,
            (YieldMode.CLAIMABLE, GasMode.CLAIMABLE, governor)
        );
        address(blast).call(blastCalldata);
    }
}
