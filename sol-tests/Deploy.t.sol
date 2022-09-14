// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../deploy/deploy.sol";
import "./TestUtils.sol";

contract DeployTest is Deploy, TestUtils {
    LibDeployConstants.DeployConstants deployConstants;

    function setUp() public onlyForked {
        // Setup deployed contracts on forked mainnet.
        deployConstants = LibDeployConstants.fork();
        run(deployConstants);
    }

    function testForked_deploy() public onlyForked {
        // Check `Globals` was deployed and all globals are set.
        assertTrue(address(globals) != address(0));
        assertTrue(globals.getAddress(LibGlobals.GLOBAL_PARTY_IMPL) != address(0));
        assertTrue(globals.getAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL) != address(0));
        assertTrue(globals.getAddress(LibGlobals.GLOBAL_PARTY_FACTORY) != address(0));
        assertTrue(globals.getAddress(LibGlobals.GLOBAL_GOVERNANCE_NFT_RENDER_IMPL) != address(0));
        assertTrue(globals.getAddress(LibGlobals.GLOBAL_CF_NFT_RENDER_IMPL) != address(0));
        assertTrue(globals.getUint256(LibGlobals.GLOBAL_OS_ZORA_AUCTION_TIMEOUT) != 0);
        assertTrue(globals.getUint256(LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION) != 0);
        assertTrue(globals.getAddress(LibGlobals.GLOBAL_AUCTION_CF_IMPL) != address(0));
        assertTrue(globals.getAddress(LibGlobals.GLOBAL_BUY_CF_IMPL) != address(0));
        assertTrue(globals.getAddress(LibGlobals.GLOBAL_COLLECTION_BUY_CF_IMPL) != address(0));
        assertTrue(globals.getUint256(LibGlobals.GLOBAL_DAO_DISTRIBUTION_SPLIT) != 0);
        assertTrue(globals.getAddress(LibGlobals.GLOBAL_DAO_WALLET) != address(0));
        assertTrue(globals.getAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR) != address(0));
        assertTrue(globals.getBytes32(LibGlobals.GLOBAL_OPENSEA_CONDUIT_KEY) != bytes32(0));
        assertTrue(globals.getAddress(LibGlobals.GLOBAL_OPENSEA_ZONE) != address(0));
        assertTrue(globals.getUint256(LibGlobals.GLOBAL_PROPOSAL_MAX_CANCEL_DURATION) != 0);
        assertTrue(globals.getUint256(LibGlobals.GLOBAL_ZORA_MIN_AUCTION_DURATION) != 0);
        assertTrue(globals.getUint256(LibGlobals.GLOBAL_ZORA_MAX_AUCTION_DURATION) != 0);
        assertTrue(globals.getUint256(LibGlobals.GLOBAL_ZORA_MAX_AUCTION_TIMEOUT) != 0);
        assertTrue(globals.getUint256(LibGlobals.GLOBAL_OS_MIN_ORDER_DURATION) != 0);
        assertTrue(globals.getUint256(LibGlobals.GLOBAL_OS_MAX_ORDER_DURATION) != 0);
        for (uint256 i; i < deployConstants.adminAddresses.length; ++i) {
            address adminAddress = deployConstants.adminAddresses[i];
            assertTrue(globals.getIncludesAddress(LibGlobals.GLOBAL_DAO_AUTHORITIES, adminAddress));
        }

        // Check that all contracts were deployed.
        assertTrue(address(zoraAuctionHouse) != address(0));
        assertTrue(address(auctionCrowdfundImpl) != address(0));
        assertTrue(address(buyCrowdfundImpl) != address(0));
        assertTrue(address(collectionBuyCrowdfundImpl) != address(0));
        assertTrue(address(partyCrowdfundFactory) != address(0));
        assertTrue(address(partyImpl) != address(0));
        assertTrue(address(partyFactory) != address(0));
        assertTrue(address(seaport) != address(0));
        assertTrue(address(proposalEngineImpl) != address(0));
        assertTrue(address(tokenDistributor) != address(0));
        assertTrue(address(partyCrowdfundNFTRenderer) != address(0));
        assertTrue(address(partyGovernanceNFTRenderer) != address(0));
        assertTrue(address(partyHelpers) != address(0));
        assertTrue(address(allowListGateKeeper) != address(0));
        assertTrue(address(tokenGateKeeper) != address(0));

        // Check that ownership of `Globals` was transferred to PartyDAO multisig.
        assertEq(globals.multiSig(), deployConstants.partyDaoMultisig);
    }
}
