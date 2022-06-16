// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';
import '../contracts/tokens/IERC721.sol';
import "../contracts/party/PartyFactory.sol";

contract RinkebyPartify is Test {
  // constants
  address constant PARTY_FACTORY_ADDRESS = 0x90e7A0bCcE74F04c246Bc72133d1F269dd463b08;
  address constant NFT_CONTRACT_ADDRESS = 0x15cBc9615CC058F6Eb9F5c584027511207C96A73;
  uint256 constant NFT_TOKEN_ID = 784;
  address constant HOST_1 = 0x8fDC86689f5F35F2b4d9f649c7bdc9C64f59e6bD;
  address constant HOST_2 = address(1);
  address constant RECIP_1 = 0x8fDC86689f5F35F2b4d9f649c7bdc9C64f59e6bD;
  address constant RECIP_2 = address(2); // TODO
  address constant RECIP_3 = address(2); // TODO
  address constant RECIP_4 = address(2); // TODO

  uint40 constant VOTE_DURATION = 200 hours;
  uint40 constant EXECUTION_DELAY = 24 hours;
  uint16 constant PASS_THRESHOLD_BPS = 5100;

  function run() public {
    vm.startBroadcast();
    IERC721 nftContract = IERC721(NFT_CONTRACT_ADDRESS);
    PartyFactory partyFactory = PartyFactory(PARTY_FACTORY_ADDRESS);

    address[] memory hosts = new address[](2);
    hosts[0] = HOST_1;
    hosts[1] = HOST_2;

    IERC721[] memory preciousTokens = new IERC721[](1);
    preciousTokens[0] = IERC721(NFT_CONTRACT_ADDRESS);

    uint256[] memory preciousTokenIds = new uint256[](1);
    preciousTokenIds[0] = NFT_TOKEN_ID;

    PartyGovernance.GovernanceOpts memory govOpts = PartyGovernance.GovernanceOpts({
      hosts: hosts,
      voteDuration: VOTE_DURATION,
      executionDelay: EXECUTION_DELAY,
      passThresholdBps: PASS_THRESHOLD_BPS,
      totalVotingPower: 100e18
    });
    Party.PartyOptions memory opts = Party.PartyOptions({
      governance: govOpts,
      name: 'Rinkeby Party',
      symbol: 'RINKS'
    });
    console.log('creating party...');
    Party party = partyFactory.createParty(tx.origin, opts, preciousTokens, preciousTokenIds);
    console.log('created party');
    console.log(address(party));

    // send NFT
    console.log('sending nft....');
    nftContract.safeTransferFrom(tx.origin, address(party), NFT_TOKEN_ID);
    console.log('sent NFT');

    console.log('minting governance NFTs....');
    // mint governance NFTs
    partyFactory.mint(party, RECIP_1, 25e18, RECIP_1);
    partyFactory.mint(party, RECIP_2, 25e18, RECIP_1);
    partyFactory.mint(party, RECIP_3, 25e18, RECIP_1);
    partyFactory.mint(party, RECIP_4, 25e18, RECIP_1);
    console.log('minted governance NFTs');
    console.log('done');
    vm.stopBroadcast();
  }



  


}