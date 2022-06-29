// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import 'forge-std/Test.sol';
import '../contracts/tokens/IERC721.sol';
import "../contracts/party/PartyFactory.sol";

contract RinkebyPartify is Test {
  // constants
  address constant PARTY_FACTORY_ADDRESS = 0x90B9831767De70462ad545128818dd6cCa692714;
  address constant NFT_CONTRACT_ADDRESS = 0x1DD9b99ce89cC088E20951b6C0F5C9c1AFdfb1c5;
  uint256 constant NFT_TOKEN_ID = 4;
  address constant HOST_1 = 0x8fDC86689f5F35F2b4d9f649c7bdc9C64f59e6bD;
  address constant HOST_2 = 0x678e8bd1D8845399c8e3C1F946CB4309014456a5;
  address constant RECIP_1 = 0xC282eC605DBe8C593380B68e18Fea69c4c628B36;
  address constant RECIP_2 = 0x8fDC86689f5F35F2b4d9f649c7bdc9C64f59e6bD; 
  address constant RECIP_3 = 0x678e8bd1D8845399c8e3C1F946CB4309014456a5;
  address constant RECIP_4 = 0x470084c5F2a31A35D44723bFD0A32f529CE21E00;
  address constant RECIP_5 = 0xcAAAE655D431bdDB3F2f20bd31BC629928131582;
  address constant RECIP_6 = 0x8fDC86689f5F35F2b4d9f649c7bdc9C64f59e6bD;
  address constant RECIP_7 = 0x678e8bd1D8845399c8e3C1F946CB4309014456a5;
  address constant RECIP_8 = 0x678e8bd1D8845399c8e3C1F946CB4309014456a5;

  uint40 constant VOTE_DURATION = 200 hours;
  uint40 constant EXECUTION_DELAY = 5 minutes;
  uint16 constant PASS_THRESHOLD_BPS = 5100;

  function run() public {
    vm.startBroadcast();
    IERC721 nftContract = IERC721(NFT_CONTRACT_ADDRESS);

    if (nftContract.ownerOf(NFT_TOKEN_ID) != tx.origin) {
      revert("dont own nft");
    }

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
      name: 'First Party',
      symbol: 'FIRST'
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
    partyFactory.mint(party, RECIP_1, 5e18, RECIP_1);
    partyFactory.mint(party, RECIP_2, 5e18, RECIP_2);
    partyFactory.mint(party, RECIP_3, 1e18, RECIP_3);
    partyFactory.mint(party, RECIP_4, 15e18, RECIP_4);
    partyFactory.mint(party, RECIP_5, 20e18, RECIP_5);
    partyFactory.mint(party, RECIP_6, 35e18, RECIP_6);
    partyFactory.mint(party, RECIP_7, 5e18, RECIP_7);
    partyFactory.mint(party, RECIP_8, 14e18, RECIP_8);
    console.log('minted governance NFTs');
    console.log('done');
    vm.stopBroadcast();
  }
}
