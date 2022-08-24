// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

// Valid keys in `IGlobals`. Append-only.
library LibGlobals {
    uint256 internal constant GLOBAL_PARTY_IMPL                     = 1;
    uint256 internal constant GLOBAL_PROPOSAL_ENGINE_IMPL           = 2;
    uint256 internal constant GLOBAL_PARTY_FACTORY                  = 3;
    uint256 internal constant GLOBAL_GOVERNANCE_NFT_RENDER_IMPL     = 4;
    uint256 internal constant GLOBAL_CF_NFT_RENDER_IMPL             = 5;
    uint256 internal constant GLOBAL_OS_ZORA_AUCTION_TIMEOUT        = 6;
    uint256 internal constant GLOBAL_OS_ZORA_AUCTION_DURATION       = 7;
    uint256 internal constant GLOBAL_PARTY_BID_IMPL                 = 8;
    uint256 internal constant GLOBAL_PARTY_BUY_IMPL                 = 9;
    uint256 internal constant GLOBAL_PARTY_COLLECTION_BUY_IMPL      = 10;
    uint256 internal constant GLOBAL_DAO_DISTRIBUTION_SPLIT         = 11;
    uint256 internal constant GLOBAL_DAO_WALLET                     = 12;
    uint256 internal constant GLOBAL_TOKEN_DISTRIBUTOR              = 13;
    uint256 internal constant GLOBAL_DAO_AUTHORITIES                = 14;
    uint256 internal constant GLOBAL_OPENSEA_CONDUIT_KEY            = 15;
    uint256 internal constant GLOBAL_OPENSEA_ZONE                   = 16;
    uint256 internal constant GLOBAL_PROPOSAL_MAX_CANCEL_DURATION   = 17;
    uint256 internal constant GLOBAL_ZORA_MIN_AUCTION_DURATION      = 18;
    uint256 internal constant GLOBAL_ROYALTY_RECEIVER               = 19;
    uint256 internal constant GLOBAL_ROYALTY_BPS                    = 20;
}
