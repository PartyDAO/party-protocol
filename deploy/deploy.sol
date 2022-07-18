// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';

import '../contracts/crowdfund/PartyBid.sol';
import '../contracts/crowdfund/PartyBuy.sol';
import '../contracts/crowdfund/PartyCollectionBuy.sol';
import '../contracts/crowdfund/PartyCrowdfundFactory.sol';
import '../contracts/distribution/TokenDistributor.sol';
import '../contracts/globals/Globals.sol';
import '../contracts/globals/LibGlobals.sol';
import '../contracts/party/Party.sol';
import '../contracts/party/PartyFactory.sol';
import '../contracts/proposals/ProposalExecutionEngine.sol';
import './LibDeployConstants.sol';

// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

    /**
     * @dev Converts an `address` with fixed length of 20 bytes to its not checksummed ASCII `string` hexadecimal representation.
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), _ADDRESS_LENGTH);
    }
}

contract Deploy is Test {

  // constants
  // dry-run deployer address
  // address constant DEPLOYER_ADDRESS = 0x00a329c0648769A73afAc7F9381E08FB43dBEA72;
  // real deployer address
  address constant DEPLOYER_ADDRESS = 0x66512B61F855478bfba669e32719dE5fD7a57Fa4; // TODO: we can set this, or we can use tx.origin

  // temporary variables to store deployed contract addresses
  Globals globals;
  IZoraAuctionHouse zoraAuctionHouse;
  PartyBid partyBidImpl;
  PartyBuy partyBuyImpl;
  PartyCollectionBuy partyCollectionBuyImpl;
  PartyCrowdfundFactory partyCrowdfundFactory;
  Party partyImpl;
  PartyFactory partyFactory;
  ISeaportExchange seaport;
  ProposalExecutionEngine proposalEngineImpl;
  TokenDistributor tokenDistributor;

  function run(LibDeployConstants.DeployConstants memory deployConstants) public {
    console.log('Starting deploy script.');
    console.log('DEPLOYER_ADDRESS', DEPLOYER_ADDRESS);
    vm.startBroadcast();

    seaport = ISeaportExchange(deployConstants.seaportExchangeAddress);

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


    // DEPLOY_SHARED_WYVERN_V2_MAKER
    console.log('');

    console.log('');
    console.log('  Globals - setting OpenSea Zora auction variables');
    globals.setUint256(LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION, deployConstants.osZoraAuctionDuration);
    console.log('  Globals - successfully set OpenSea Zora auction duration', deployConstants.osZoraAuctionDuration);
    globals.setUint256(LibGlobals.GLOBAL_OS_ZORA_AUCTION_TIMEOUT, deployConstants.osZoraAuctionTimeout);
    console.log('  Globals - successfully set OpenSea Zora auction timeout', deployConstants.osZoraAuctionTimeout);


    // DEPLOY_PROPOSAL_EXECUTION_ENGINE
    console.log('');
    console.log('### ProposalExecutionEngine');
    console.log('  Deploying - ProposalExecutionEngine');
    zoraAuctionHouse = IZoraAuctionHouse(deployConstants.zoraAuctionHouseAddress);
    ISeaportConduitController conduitController = ISeaportConduitController(deployConstants.osConduitController);
    proposalEngineImpl = new ProposalExecutionEngine(globals, seaport, conduitController, zoraAuctionHouse);
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


    // DEPLOY_PARTY_BID_IMPLEMENTATION
    console.log('');
    console.log('### PartyBid crowdfund implementation');
    console.log('  Deploying - PartyBid crowdfund implementation');
    partyBidImpl = new PartyBid(globals);
    console.log('  Deployed - PartyBid crowdfund implementation', address(partyBidImpl));

    console.log('');
    console.log('  Globals - setting PartyBid crowdfund implementation address');
    globals.setAddress(LibGlobals.GLOBAL_PARTY_BID_IMPL, address(partyBidImpl));
    console.log('  Globals - successfully set PartyBid crowdfund implementation address', address(partyBidImpl));


    // DEPLOY_PARTY_BUY_IMPLEMENTATION
    console.log('');
    console.log('### PartyBuy crowdfund implementation');
    console.log('  Deploying - PartyBuy crowdfund implementation');
    partyBuyImpl = new PartyBuy(globals);
    console.log('  Deployed - PartyBuy crowdfund implementation', address(partyBuyImpl));

    console.log('');
    console.log('  Globals - setting PartyBuy crowdfund implementation address');
    globals.setAddress(LibGlobals.GLOBAL_PARTY_BUY_IMPL, address(partyBuyImpl));
    console.log('  Globals - successfully set PartyBuy crowdfund implementation address', address(partyBuyImpl));


    // DEPLOY_PARTY_COLLECTION_BUY_IMPLEMENTATION
    console.log('');
    console.log('### PartyCollectionBuy crowdfund implementation');
    console.log('  Deploying - PartyCollectionBuy crowdfund implementation');
    partyCollectionBuyImpl = new PartyCollectionBuy(globals);
    console.log('  Deployed - PartyCollectionBuy crowdfund implementation', address(partyCollectionBuyImpl));

    console.log('');
    console.log('  Globals - setting PartyCollectionBuy crowdfund implementation address');
    globals.setAddress(LibGlobals.GLOBAL_PARTY_COLLECTION_BUY_IMPL, address(partyCollectionBuyImpl));
    console.log('  Globals - successfully set PartyCollectionBuy crowdfund implementation address', address(partyCollectionBuyImpl));


    // DEPLOY_PARTY_CROWDFUND_FACTORY
    console.log('');
    console.log('### PartyCrowdfundFactory');
    console.log('  Deploying - PartyCrowdfundFactory');
    partyCrowdfundFactory = new PartyCrowdfundFactory(globals);
    console.log('  Deployed - PartyCrowdfundFactory', address(partyCrowdfundFactory));


    // TODO: TRANSFER_OWNERSHIP_TO_PARTYDAO_MULTISIG
    // console.log('');
    // console.log('### Transfer MultiSig');
    // console.log('  Transferring ownership to PartyDAO multi-sig', deployConstants.partyDaoMultisig);
    // globals.transferMultiSig(deployConstants.partyDaoMultisig);
    // console.log('  Transferred ownership to', deployConstants.partyDaoMultisig);


    // Output deployed addresses in JSON format
    console.log('');
    console.log('### Deployed addresses JSON');
    console.log('{');
    console.log(string.concat('  "globals": "', Strings.toHexString(address(globals)) ,'",'));
    console.log(string.concat('  "tokenDistributor": "', Strings.toHexString(address(tokenDistributor)) ,'",'));
    console.log(string.concat('  "seaportExchange": "', Strings.toHexString(address(seaport)) ,'",'));
    console.log(string.concat('  "proposalEngineImpl": "', Strings.toHexString(address(proposalEngineImpl)) ,'",'));
    console.log(string.concat('  "partyImpl": "', Strings.toHexString(address(partyImpl)) ,'",'));
    console.log(string.concat('  "partyFactory": "', Strings.toHexString(address(partyFactory)) ,'",'));
    console.log(string.concat('  "partyBidImpl": "', Strings.toHexString(address(partyBidImpl)) ,'",'));
    console.log(string.concat('  "partyBuyImpl": "', Strings.toHexString(address(partyBuyImpl)) ,'",'));
    console.log(string.concat('  "partyCollectionBuyImpl": "', Strings.toHexString(address(partyCollectionBuyImpl)) ,'",'));
    console.log(string.concat('  "partyCrowdfundFactory": "', Strings.toHexString(address(partyCrowdfundFactory)) ,'"'));
    // NOTE: ensure trailing comma on second to last line
    console.log('}');

    vm.stopBroadcast();
    console.log('');
    console.log('Ending deploy script.');
  }
}
