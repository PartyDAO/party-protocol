// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';

// import '../contracts/crowdfund/PartyCrowdfundFactory.sol';
import '../contracts/distribution/TokenDistributor.sol';
import '../contracts/globals/Globals.sol';
import '../contracts/globals/LibGlobals.sol';
import '../contracts/party/Party.sol';
import '../contracts/party/PartyFactory.sol';
import '../contracts/proposals/ProposalExecutionEngine.sol';
import '../contracts/proposals/opensea/SharedWyvernV2Maker.sol';

contract Deploy is Test {

  // TODO: verify these constants
  // constants
  address constant DEPLOYER_ADDRESS = 0x00a329c0648769A73afAc7F9381E08FB43dBEA72;
  address constant OPENSEA_EXCHANGE_ADDRESS = 0x7f268357A8c2552623316e2562D90e642bB538E5;
  address constant PARTY_DAO_MULTISIG = 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f;
  uint256 constant PARTY_DAO_DISTRIBUTION_SPLIT_BPS = 250;
  uint256 constant OS_ZORA_AUCTION_DURATION = 86400; // 60 * 60 * 24 = 86400 seconds = 24 hours
  address constant ZORA_AUCTION_HOUSE_ADDRESS = 0xE468cE99444174Bd3bBBEd09209577d25D1ad673;

  // temporary variables to store deployed contract addresses
  // PartyCrowdfundFactory partyCrowdfundFactoryAddress;
  Globals globals;
  IWyvernExchangeV2 openseaExchange;
  IZoraAuctionHouse zoraAuctionHouse;
  Party partyImpl;
  PartyFactory partyFactory;
  ProposalExecutionEngine proposalEngineImpl;
  SharedWyvernV2Maker sharedWyvernV2Maker;
  TokenDistributor tokenDistributor;

  function run() public {
    console.log('Starting deploy script.');
    console.log('DEPLOYER_ADDRESS', DEPLOYER_ADDRESS);
    vm.startBroadcast();

    // DEPLOY_GLOBALS
    console.log('');
    console.log('Deploying - Globals');
    globals = new Globals(DEPLOYER_ADDRESS);
    console.log('Deployed - Globals', address(globals));

    console.log('  Globals - setting PartyDao Multi-sig address');
    // TODO: setAddress or setUint256?
    globals.setAddress(LibGlobals.GLOBAL_DAO_WALLET, PARTY_DAO_MULTISIG);
    console.log('  Globals - successfully set PartyDao multi-sig address', PARTY_DAO_MULTISIG);

    console.log('  Globals - setting PartyDao split basis points');
    globals.setUint256(LibGlobals.GLOBAL_DAO_DISTRIBUTION_SPLIT, PARTY_DAO_DISTRIBUTION_SPLIT_BPS);
    console.log('  Globals - successfully set PartyDao split basis points', PARTY_DAO_DISTRIBUTION_SPLIT_BPS);


    // DEPLOY_TOKEN_DISTRIBUTOR
    console.log('');
    console.log('Deploying - TokenDistributor');
    tokenDistributor = new TokenDistributor(globals);
    console.log('Deployed - TokenDistributor', address(tokenDistributor));

    console.log('  Globals - setting Token Distributor address');
    globals.setAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR, address(tokenDistributor));
    console.log('  Globals - successfully set Token Distributor address', address(tokenDistributor));


    // DEPLOY_SHARED_WYVERN_V2_MAKER
    console.log('');
    console.log('Deploying - SharedWyvernV2Maker');
    openseaExchange = IWyvernExchangeV2(OPENSEA_EXCHANGE_ADDRESS);
    sharedWyvernV2Maker = new SharedWyvernV2Maker(openseaExchange);
    console.log('Deployed - SharedWyvernV2Maker', address(sharedWyvernV2Maker));

    console.log('  Globals - setting OpenSea Zora auction duration');
    globals.setUint256(LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION, OS_ZORA_AUCTION_DURATION);
    console.log('  Globals - successfully set OpenSea Zora auction duration', OS_ZORA_AUCTION_DURATION);


    // DEPLOY_PROPOSAL_EXECUTION_ENGINE
    console.log('');
    console.log('Deploying - ProposalExecutionEngine');
    zoraAuctionHouse = IZoraAuctionHouse(ZORA_AUCTION_HOUSE_ADDRESS);
    proposalEngineImpl = new ProposalExecutionEngine(globals, sharedWyvernV2Maker, zoraAuctionHouse);
    console.log('Deployed - ProposalExecutionEngine', address(proposalEngineImpl));
    console.log('  with wyvern', address(sharedWyvernV2Maker));
    console.log('  with zora auction house', address(zoraAuctionHouse));

    console.log('  Globals - setting Proposal engine implementation address');
    globals.setAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL, address(proposalEngineImpl));
    console.log('  Globals - successfully set Proposal engine implementation address', address(proposalEngineImpl));


    // DEPLOY_PARTY_IMPLEMENTATION
    console.log('');
    console.log('Deploying - Party implementation');
    partyImpl = new Party(globals);
    console.log('Deployed - Party implementation', address(partyImpl));

    console.log('  Globals - setting Party implementation address');
    globals.setAddress(LibGlobals.GLOBAL_PARTY_IMPL, address(partyImpl));
    console.log('  Globals - successfully set Party implementation address', address(partyImpl));


    // DEPLOY_PARTY_FACTORY
    console.log('');
    console.log('Deploying - PartyFactory');
    partyFactory = new PartyFactory(globals);
    console.log('Deployed - PartyFactory', address(partyFactory));

    console.log('  Globals - setting Party Factory address');
    globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
    console.log('  Globals - successfully set Party Factory address', address(partyFactory));


    // TODO: DEPLOY_PARTY_CROWDFUND_FACTORY
    // console.log('');
    // console.log('Deploying - PartyCrowdfundFactory');
    // partyCrowdfundFactoryAddress = new PartyCrowdfundFactory();
    // console.log('Deployed - PartyCrowdfundFactory', address(partyCrowdfundFactoryAddress));

    // TODO: TRANSFER_OWNERSHIP_TO_PARTYDAO_MULTISIG
    // globals.transferOwnership(PARTY_DAO_MULTISIG);

    vm.stopBroadcast();
    console.log('');
    console.log('Ending deploy script.');
  }
}
