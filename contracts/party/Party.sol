// SPDX-License-Identifier: UNLICENSED
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
    }

    function initialize(bytes memory initData)
        external
        override
        onlyDelegateCall
    {
        PartyInitData memory initData_ = abi.decode(initData, (PartyInitData));
        PartyGovernanceNFT._initialize(
            initData_.name,
            initData_.symbol,
            initData_.governance,
            initData_.preciousToken,
            initData_.preciousTokenId
        );
    }
}
