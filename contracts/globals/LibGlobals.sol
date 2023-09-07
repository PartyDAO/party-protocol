// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

// Valid keys in `IGlobals`. Append-only.
library LibGlobals {
    // The Globals commented out below were depreciated in 1.2; factories
    // can now choose the implementation address to deploy and no longer
    // deploy the latest implementation. They will no longer be updated
    // in future releases.
    //
    // See https://github.com/PartyDAO/party-migrations for
    // implementation addresses by release.

    uint256 internal constant GLOBAL_PARTY_IMPL = 1;
    uint256 internal constant GLOBAL_PROPOSAL_ENGINE_IMPL = 2;
    uint256 internal constant GLOBAL_PARTY_FACTORY = 3;
    uint256 internal constant GLOBAL_GOVERNANCE_NFT_RENDER_IMPL = 4;
    uint256 internal constant GLOBAL_CF_NFT_RENDER_IMPL = 5;
    uint256 internal constant GLOBAL_OS_ZORA_AUCTION_TIMEOUT = 6;
    uint256 internal constant GLOBAL_OS_ZORA_AUCTION_DURATION = 7;
    // uint256 internal constant GLOBAL_AUCTION_CF_IMPL = 8;
    // uint256 internal constant GLOBAL_BUY_CF_IMPL = 9;
    // uint256 internal constant GLOBAL_COLLECTION_BUY_CF_IMPL = 10;
    uint256 internal constant GLOBAL_DAO_WALLET = 11;
    uint256 internal constant GLOBAL_TOKEN_DISTRIBUTOR = 12;
    uint256 internal constant GLOBAL_OPENSEA_CONDUIT_KEY = 13;
    uint256 internal constant GLOBAL_OPENSEA_ZONE = 14;
    uint256 internal constant GLOBAL_PROPOSAL_MAX_CANCEL_DURATION = 15;
    uint256 internal constant GLOBAL_ZORA_MIN_AUCTION_DURATION = 16;
    uint256 internal constant GLOBAL_ZORA_MAX_AUCTION_DURATION = 17;
    uint256 internal constant GLOBAL_ZORA_MAX_AUCTION_TIMEOUT = 18;
    uint256 internal constant GLOBAL_OS_MIN_ORDER_DURATION = 19;
    uint256 internal constant GLOBAL_OS_MAX_ORDER_DURATION = 20;
    uint256 internal constant GLOBAL_DISABLE_PARTY_ACTIONS = 21;
    uint256 internal constant GLOBAL_RENDERER_STORAGE = 22;
    uint256 internal constant GLOBAL_PROPOSAL_MIN_CANCEL_DURATION = 23;
    // uint256 internal constant GLOBAL_ROLLING_AUCTION_CF_IMPL = 24;
    // uint256 internal constant GLOBAL_COLLECTION_BATCH_BUY_CF_IMPL = 25;
    uint256 internal constant GLOBAL_METADATA_REGISTRY = 26;
    // uint256 internal constant GLOBAL_CROWDFUND_FACTORY = 27;
    // uint256 internal constant GLOBAL_INITIAL_ETH_CF_IMPL = 28;
    // uint256 internal constant GLOBAL_RERAISE_ETH_CF_IMPL = 29;
    uint256 internal constant GLOBAL_SEAPORT = 30;
    uint256 internal constant GLOBAL_CONDUIT_CONTROLLER = 31;
}
