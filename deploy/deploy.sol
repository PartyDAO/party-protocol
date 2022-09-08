// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Script.sol';

import '../contracts/crowdfund/AuctionCrowdfund.sol';
import '../contracts/crowdfund/BuyCrowdfund.sol';
import '../contracts/crowdfund/CollectionBuyCrowdfund.sol';
import '../contracts/crowdfund/CrowdfundFactory.sol';
import '../contracts/distribution/TokenDistributor.sol';
import '../contracts/gatekeepers/AllowListGateKeeper.sol';
import '../contracts/gatekeepers/TokenGateKeeper.sol';
import '../contracts/gatekeepers/IGateKeeper.sol';
import '../contracts/globals/Globals.sol';
import '../contracts/globals/LibGlobals.sol';
import '../contracts/party/Party.sol';
import '../contracts/party/PartyFactory.sol';
import '../contracts/renderers/CrowdfundNFTRenderer.sol';
import '../contracts/renderers/PartyGovernanceNFTRenderer.sol';
import '../contracts/proposals/ProposalExecutionEngine.sol';
import '../contracts/utils/PartyHelpers.sol';
import './LibDeployConstants.sol';

contract Deploy is Script {
  struct AddressMapping {
    string key;
    address value;
  }

  // constants
  // dry-run deployer address
  // address constant DEPLOYER_ADDRESS = 0x00a329c0648769A73afAc7F9381E08FB43dBEA72;
  // real deployer address
  address constant DEPLOYER_ADDRESS = 0x8fDC86689f5F35F2b4d9f649c7bdc9C64f59e6bD; // TODO: we can set this, or we can use tx.origin

  // temporary variables to store deployed contract addresses
  Globals globals;
  IZoraAuctionHouse zoraAuctionHouse;
  AuctionCrowdfund auctionCrowdfundImpl;
  BuyCrowdfund buyCrowdfundImpl;
  CollectionBuyCrowdfund collectionBuyCrowdfundImpl;
  CrowdfundFactory partyCrowdfundFactory;
  Party partyImpl;
  PartyFactory partyFactory;
  IOpenseaExchange seaport;
  ProposalExecutionEngine proposalEngineImpl;
  TokenDistributor tokenDistributor;
  CrowdfundNFTRenderer partyCrowdfundNFTRenderer;
  PartyGovernanceNFTRenderer partyGovernanceNFTRenderer;
  PartyHelpers partyHelpers;
  IGateKeeper allowListGateKeeper;
  IGateKeeper tokenGateKeeper;

  function run(LibDeployConstants.DeployConstants memory deployConstants) public {
    console.log('Starting deploy script.');
    console.log('DEPLOYER_ADDRESS', DEPLOYER_ADDRESS);
    vm.startBroadcast();

    seaport = IOpenseaExchange(deployConstants.seaportExchangeAddress);

    // DEPLOY_GLOBALS
    console.log('');
    console.log('### Globals');
    console.log('  Deploying - Globals');
    globals = new Globals(DEPLOYER_ADDRESS);
    console.log('  Deployed - Globals', address(globals));

    console.log('');
    console.log('  Globals - setting PartyDao Multi-sig address');
    // globals.setAddress(LibGlobals.GLOBAL_DAO_WALLET, deployConstants.partyDaoMultisig);
    // console.log('  Globals - successfully set PartyDao multi-sig address', deployConstants.partyDaoMultisig);
    // development/testnet deploy
    globals.setAddress(LibGlobals.GLOBAL_DAO_WALLET, DEPLOYER_ADDRESS);
    console.log('  Globals - successfully set PartyDao multi-sig address', DEPLOYER_ADDRESS);

    console.log('');
    console.log('  Globals - setting DAO authority addresses', deployConstants.adminAddresses.length);
    uint256 i;
    for (i = 0; i < deployConstants.adminAddresses.length; ++i) {
      address adminAddress = deployConstants.adminAddresses[i];
      console.log('  Globals - setting DAO authority address', adminAddress);
      globals.setIncludesAddress(LibGlobals.GLOBAL_DAO_AUTHORITIES, adminAddress, true);
      console.log('  Globals - set DAO authority address', adminAddress);
    }
    console.log('  Globals - successfully set DAO authority addresses');

    console.log('  Globals - setting PartyDao split basis points');
    globals.setUint256(LibGlobals.GLOBAL_DAO_DISTRIBUTION_SPLIT, deployConstants.partyDaoDistributionSplitBps);
    console.log('  Globals - successfully set PartyDao split basis points', deployConstants.partyDaoDistributionSplitBps);

    console.log('  Globals - setting seaport params');
    globals.setBytes32(
        LibGlobals.GLOBAL_OPENSEA_CONDUIT_KEY,
        deployConstants.osConduitKey
    );
    globals.setAddress(
        LibGlobals.GLOBAL_OPENSEA_ZONE,
        deployConstants.osZone
    );
    console.log('  Globals - successfully set seaport values:');
    console.logBytes32(deployConstants.osConduitKey);
    console.log(deployConstants.osZone);


    // DEPLOY_TOKEN_DISTRIBUTOR
    console.log('');
    console.log('### TokenDistributor');
    console.log('  Deploying - TokenDistributor');
    tokenDistributor = new TokenDistributor(globals);
    console.log('  Deployed - TokenDistributor', address(tokenDistributor));

    console.log('');
    console.log('  Globals - setting Token Distributor address');
    globals.setAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR, address(tokenDistributor));
    console.log('  Globals - successfully set Token Distributor address', address(tokenDistributor));


    console.log('');

    console.log('');
    console.log('  Globals - setting OpenSea and Zora auction variables');
    globals.setUint256(LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION, deployConstants.osZoraAuctionDuration);
    console.log('  Globals - successfully set OpenSea Zora auction duration', deployConstants.osZoraAuctionDuration);
    globals.setUint256(LibGlobals.GLOBAL_OS_ZORA_AUCTION_TIMEOUT, deployConstants.osZoraAuctionTimeout);
    console.log('  Globals - successfully set OpenSea Zora auction timeout', deployConstants.osZoraAuctionTimeout);
    globals.setUint256(LibGlobals.GLOBAL_OS_MIN_ORDER_DURATION, deployConstants.osMinOrderDuration);
    console.log('  Globals - successfully set OpenSea min order duration', deployConstants.osMinOrderDuration);
    globals.setUint256(LibGlobals.GLOBAL_OS_MAX_ORDER_DURATION, deployConstants.osMaxOrderDuration);
    console.log('  Globals - successfully set OpenSea max order duration', deployConstants.osMaxOrderDuration);
    globals.setUint256(LibGlobals.GLOBAL_ZORA_MIN_AUCTION_DURATION, deployConstants.zoraMinAuctionDuration);
    console.log('  Globals - successfully set Zora min auction duration', deployConstants.zoraMinAuctionDuration);
    globals.setUint256(LibGlobals.GLOBAL_ZORA_MAX_AUCTION_DURATION, deployConstants.zoraMaxAuctionDuration);
    console.log('  Globals - successfully set Zora max auction duration', deployConstants.zoraMaxAuctionDuration);
    globals.setUint256(LibGlobals.GLOBAL_ZORA_MAX_AUCTION_TIMEOUT, deployConstants.zoraMaxAuctionTimeout);
    console.log('  Globals - successfully set Zora max auction timeout', deployConstants.zoraMaxAuctionTimeout);


    // DEPLOY_PROPOSAL_EXECUTION_ENGINE
    console.log('');
    console.log('### ProposalExecutionEngine');
    console.log('  Deploying - ProposalExecutionEngine');
    zoraAuctionHouse = IZoraAuctionHouse(deployConstants.zoraAuctionHouseAddress);
    IOpenseaConduitController conduitController = IOpenseaConduitController(deployConstants.osConduitController);
    IFractionalV1VaultFactory fractionalVaultFactory = IFractionalV1VaultFactory(deployConstants.fractionalVaultFactory);
    proposalEngineImpl = new ProposalExecutionEngine(globals, seaport, conduitController, zoraAuctionHouse, fractionalVaultFactory);
    console.log('  Deployed - ProposalExecutionEngine', address(proposalEngineImpl));
    console.log('    with seaport', address(seaport));
    console.log('    with zora auction house', address(zoraAuctionHouse));

    console.log('');
    console.log('  Globals - setting Proposal engine implementation address');
    globals.setAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL, address(proposalEngineImpl));
    console.log('  Globals - successfully set Proposal engine implementation address', address(proposalEngineImpl));


    // DEPLOY_PARTY_IMPLEMENTATION
    console.log('');
    console.log('### Party implementation');
    console.log('  Deploying - Party implementation');
    partyImpl = new Party(globals);
    console.log('  Deployed - Party implementation', address(partyImpl));

    console.log('');
    console.log('  Globals - setting Party implementation address');
    globals.setAddress(LibGlobals.GLOBAL_PARTY_IMPL, address(partyImpl));
    console.log('  Globals - successfully set Party implementation address', address(partyImpl));


    // DEPLOY_PARTY_FACTORY
    console.log('');
    console.log('### PartyFactory');
    console.log('  Deploying - PartyFactory');
    partyFactory = new PartyFactory(globals);
    console.log('  Deployed - PartyFactory', address(partyFactory));

    console.log('');
    console.log('  Globals - setting Party Factory address');
    globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
    console.log('  Globals - successfully set Party Factory address', address(partyFactory));


    // DEPLOY_AUCTION_CF_IMPLEMENTATION
    console.log('');
    console.log('### AuctionCrowdfund crowdfund implementation');
    console.log('  Deploying - AuctionCrowdfund crowdfund implementation');
    auctionCrowdfundImpl = new AuctionCrowdfund(globals);
    console.log('  Deployed - AuctionCrowdfund crowdfund implementation', address(auctionCrowdfundImpl));

    console.log('');
    console.log('  Globals - setting AuctionCrowdfund crowdfund implementation address');
    globals.setAddress(LibGlobals.GLOBAL_AUCTION_CF_IMPL, address(auctionCrowdfundImpl));
    console.log('  Globals - successfully set AuctionCrowdfund crowdfund implementation address', address(auctionCrowdfundImpl));


    // DEPLOY_BUY_CF_IMPLEMENTATION
    console.log('');
    console.log('### BuyCrowdfund crowdfund implementation');
    console.log('  Deploying - BuyCrowdfund crowdfund implementation');
    buyCrowdfundImpl = new BuyCrowdfund(globals);
    console.log('  Deployed - BuyCrowdfund crowdfund implementation', address(buyCrowdfundImpl));

    console.log('');
    console.log('  Globals - setting BuyCrowdfund crowdfund implementation address');
    globals.setAddress(LibGlobals.GLOBAL_BUY_CF_IMPL, address(buyCrowdfundImpl));
    console.log('  Globals - successfully set BuyCrowdfund crowdfund implementation address', address(buyCrowdfundImpl));


    // DEPLOY_COLLECTION_BUY_CF_IMPLEMENTATION
    console.log('');
    console.log('### CollectionBuyCrowdfund crowdfund implementation');
    console.log('  Deploying - CollectionBuyCrowdfund crowdfund implementation');
    collectionBuyCrowdfundImpl = new CollectionBuyCrowdfund(globals);
    console.log('  Deployed - CollectionBuyCrowdfund crowdfund implementation', address(collectionBuyCrowdfundImpl));

    console.log('');
    console.log('  Globals - setting CollectionBuyCrowdfund crowdfund implementation address');
    globals.setAddress(LibGlobals.GLOBAL_COLLECTION_BUY_CF_IMPL, address(collectionBuyCrowdfundImpl));
    console.log('  Globals - successfully set CollectionBuyCrowdfund crowdfund implementation address', address(collectionBuyCrowdfundImpl));


    // DEPLOY_PARTY_CROWDFUND_FACTORY
    console.log('');
    console.log('### CrowdfundFactory');
    console.log('  Deploying - CrowdfundFactory');
    partyCrowdfundFactory = new CrowdfundFactory(globals);
    console.log('  Deployed - CrowdfundFactory', address(partyCrowdfundFactory));

    // DEPLOY_PARTY_CROWDFUND_NFT_RENDERER
    console.log('');
    console.log('### CrowdfundNFTRenderer');
    console.log('  Deploying - CrowdfundNFTRenderer');
    partyCrowdfundNFTRenderer = new CrowdfundNFTRenderer(globals);
    console.log('  Deployed - CrowdfundNFTRenderer', address(partyCrowdfundNFTRenderer));

    console.log('');
    console.log('  Globals - setting CrowdfundNFTRenderer address');
    globals.setAddress(LibGlobals.GLOBAL_CF_NFT_RENDER_IMPL, address(partyCrowdfundNFTRenderer));
    console.log('  Globals - successfully set CrowdfundNFTRenderer', address(partyCrowdfundNFTRenderer));


    // DEPLOY_PARTY_GOVERNANCE_NFT_RENDERER
    console.log('');
    console.log('### PartyGovernanceNFTRenderer');
    console.log('  Deploying - PartyGovernanceNFTRenderer');
    partyGovernanceNFTRenderer = new PartyGovernanceNFTRenderer(globals);
    console.log('  Deployed - PartyGovernanceNFTRenderer', address(partyGovernanceNFTRenderer));

    console.log('');
    console.log('  Globals - setting PartyGovernanceNFTRenderer address');
    globals.setAddress(LibGlobals.GLOBAL_GOVERNANCE_NFT_RENDER_IMPL, address(partyGovernanceNFTRenderer));
    console.log('  Globals - successfully set PartyGovernanceNFTRenderer', address(partyGovernanceNFTRenderer));

    // DEPLOY_PARTY_HELPERS
    console.log('');
    console.log('### PartyHelpers');
    console.log('  Deploying - PartyHelpers');
    partyHelpers = new PartyHelpers();
    console.log('  Deployed - PartyHelpers', address(partyHelpers));

    // DEPLOY_GATE_KEEPRS
    console.log('');
    console.log('### GateKeepers');
    console.log('  Deploying - AllowListGateKeeper');
    allowListGateKeeper = new AllowListGateKeeper();
    console.log('  Deployed - AllowListGateKeeper', address(allowListGateKeeper));

    console.log('  Deploying - TokenGateKeeper');
    tokenGateKeeper = new TokenGateKeeper();
    console.log('  Deployed - TokenGateKeeper', address(tokenGateKeeper));

    // TODO: TRANSFER_OWNERSHIP_TO_PARTYDAO_MULTISIG
    // console.log('');
    // console.log('### Transfer MultiSig');
    // console.log('  Transferring ownership to PartyDAO multi-sig', deployConstants.partyDaoMultisig);
    // globals.transferMultiSig(deployConstants.partyDaoMultisig);
    // console.log('  Transferred ownership to', deployConstants.partyDaoMultisig);


    AddressMapping[] memory addressMapping = new AddressMapping[](15);
    addressMapping[0] = AddressMapping('globals', address(globals));
    addressMapping[1] = AddressMapping('tokenDistributor', address(tokenDistributor));
    addressMapping[2] = AddressMapping('seaportExchange', address(seaport));
    addressMapping[3] = AddressMapping('proposalEngineImpl', address(proposalEngineImpl));
    addressMapping[4] = AddressMapping('partyImpl', address(partyImpl));
    addressMapping[5] = AddressMapping('partyFactory', address(partyFactory));
    addressMapping[6] = AddressMapping('auctionCrowdfundImpl', address(auctionCrowdfundImpl));
    addressMapping[7] = AddressMapping('buyCrowdfundImpl', address(buyCrowdfundImpl));
    addressMapping[8] = AddressMapping('collectionBuyCrowdfundImpl', address(collectionBuyCrowdfundImpl));
    addressMapping[9] = AddressMapping('partyCrowdfundFactory', address(partyCrowdfundFactory));
    addressMapping[10] = AddressMapping('partyCrowdfundNFTRenderer', address(partyCrowdfundNFTRenderer));
    addressMapping[11] = AddressMapping('partyGovernanceNFTRenderer', address(partyGovernanceNFTRenderer));
    addressMapping[12] = AddressMapping('partyHelpers', address(partyHelpers));
    addressMapping[13] = AddressMapping('allowListGateKeeper', address(allowListGateKeeper));
    addressMapping[14] = AddressMapping('tokenGateKeeper', address(tokenGateKeeper));

    console.log('');
    console.log('### Deployed addresses');
    string memory jsonRes = generateJSONString(addressMapping);
    console.log(jsonRes);

    vm.stopBroadcast();
    writeAddressesToFile(deployConstants.networkName, jsonRes);
    writeAbisToFiles();
    console.log('');
    console.log('Ending deploy script.');
  }

  function generateJSONString(AddressMapping[] memory parts) private pure returns (string memory) {
    string memory vals = '';
    for (uint256 i=0; i < parts.length; ++i) {
      string memory newValue = string.concat('"', parts[i].key, '": "', Strings.toHexString(parts[i].value), '"');
      if (i != parts.length - 1) {
          newValue = string.concat(newValue, ",");
      }
      vals = string.concat(vals, newValue);
    }
    return string.concat('{', vals, '}');
  }

  function writeAbisToFiles() private {
    string[] memory ffiCmd = new string[](2);
    ffiCmd[0] = "node";
    ffiCmd[1] = "./js/utils/output-abis.js";
    bytes memory ffiResp = vm.ffi(ffiCmd);

    bool wroteSuccessfully = keccak256(ffiResp) == keccak256(hex"0000000000000000000000000000000000000001");
    if (!wroteSuccessfully) {
      revert("Could not write ABIs to file");
    }
    console.log("Successfully wrote ABIS to files");
  }

  function writeAddressesToFile(string memory networkName, string memory jsonRes) private {
    string[] memory ffiCmd = new string[](4);
    ffiCmd[0] = "node";
    ffiCmd[1] = "./js/utils/save-json.js";
    ffiCmd[2] = networkName;
    ffiCmd[3] = jsonRes;
    bytes memory ffiResp = vm.ffi(ffiCmd);

    bool wroteSuccessfully = keccak256(ffiResp) == keccak256(hex"0000000000000000000000000000000000000001");
    if (!wroteSuccessfully) {
      revert("Could not write to file");
    }
    console.log("Successfully wrote to file");
  }

}
