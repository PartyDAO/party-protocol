// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

// Valid keys in `IGlobals`. Append-only.
library LibGlobals {
    uint256 internal constant GLOBAL_PARTY_IMPL                 = 1;
    uint256 internal constant GLOBAL_PROPOSAL_ENGINE_IMPL       = 2;
    uint256 internal constant GLOBAL_PARTY_FACTORY              = 3;
    uint256 internal constant GLOBAL_GOVERNANCE_NFT_RENDER_IMPL = 4;
    uint256 internal constant GLOBAL_CF_NFT_RENDER_IMPL         = 5;
    uint256 internal constant GLOBAL_OS_ZORA_AUCTION_DURATION   = 6;
    uint256 internal constant GLOBAL_PARTY_BID_IMPL             = 7;
    uint256 internal constant GLOBAL_PARTY_BUY_IMPL             = 8;
    // TODO: needed?
    uint256 internal constant GLOBAL_DAO_CF_SPLIT               = 9;
    uint256 internal constant GLOBAL_DAO_DISTRIBUTION_SPLIT     = 10;
    uint256 internal constant GLOBAL_DAO_WALLET                 = 11;
    uint256 internal constant GLOBAL_TOKEN_DISTRIBUTOR          = 12;
}
