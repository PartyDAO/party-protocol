// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../utils/Implementation.sol";
import "../tokens/IERC721.sol";

import "./PartyGovernanceNFT.sol";
import "./PartyGovernance.sol";

// Party implementation.
contract Party is Implementation, PartyGovernanceNFT {
    struct PartyOptions {
        PartyGovernance.GovernanceOpts governance;
        string name;
        string symbol;
    }

    struct PartyInitData {
        PartyOptions options;
        IERC721 preciousToken;
        uint256 preciousTokenId;
        address mintAuthority;
    }

    constructor(IGlobals globals) PartyGovernanceNFT(globals) {}

    function initialize(PartyInitData memory initData)
        external
        onlyDelegateCall
    {
        PartyGovernanceNFT._initialize(
            initData.options.name,
            initData.options.symbol,
            initData.options.governance,
            initData.preciousToken,
            initData.preciousTokenId,
            initData.mintAuthority
        );
    }

    receive() external payable {}
}
