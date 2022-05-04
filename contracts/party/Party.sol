// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Party implementation.
contract Party is Implementation, PartyGovernanceNFT {
    struct PartyOptions {
        PartyGovernance.GovernanceOpts governance;
        string name;
        string symbol;
    }

    function initialize(bytes memory initData)
        public
        override
        onlyDelegateCall
    {
        PartyOptions memory opts = abi.decode(initData, (PartyOptions));
        PartyGovernanceNFT.initialize(
            opts.name,
            opts.symbol,
            opts.governance
        );
    }
}
