// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Party implementation.
contract Party is Implementation, PartyGovernanceNFT {
    struct PartyOptions {
        PartyGovernance.GovernanceOpts governance;
        uint128 totalVotingSupply;
        string name;
        string symbol;
        IERC721 erc721Token;
        uint256 erc721TokenId;
    }

    function initialize(bytes memory initData) external onlyDelegateCall {
        PartyOptions memory opts = abi.decode(initData, (PartyOptions));
        PartyGovernanceNFT._initialize(
            opts.name,
            opts.symbol,
            opts.governance,
        );
    }
}
