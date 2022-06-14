// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/proposals/ProposalExecutionEngine.sol";

import "../../contracts/proposals/opensea/SharedWyvernV2Maker.sol";


import "../TestUtils.sol";
import "../DummyERC721.sol";
import "./ZoraTestUtils.sol";
import "../TestUsers.sol";

contract ListOnZoraProposalIntegrationTest is
    Test,
    TestUtils,
    ZoraTestUtils
{
    IZoraAuctionHouse ZORA =
        IZoraAuctionHouse(0xE468cE99444174Bd3bBBEd09209577d25D1ad673);

    constructor() ZoraTestUtils(ZORA) {}

    function setUp() public onlyForked {
    }

    function testSimpleZora() public onlyForked {
      GlobalsAdmin globalsAdmin = new GlobalsAdmin();
      Globals globals = globalsAdmin.globals();
      Party partyImpl = new Party(globals);
      globalsAdmin.setPartyImpl(address(partyImpl));
      address globalDaoWalletAddress = address(420);
      globalsAdmin.setGlobalDaoWallet(globalDaoWalletAddress);

      IWyvernExchangeV2 wyvern = IWyvernExchangeV2(address(0x7f268357A8c2552623316e2562D90e642bB538E5));
      SharedWyvernV2Maker wyvernMaker = new SharedWyvernV2Maker(wyvern);
      ProposalExecutionEngine pe = new ProposalExecutionEngine(globals, wyvernMaker, ZORA);
      globalsAdmin.setProposalEng(address(pe));

      PartyFactory partyFactory = new PartyFactory(globals);

      PartyParticipant john = new PartyParticipant();
      PartyParticipant danny = new PartyParticipant();
      PartyParticipant steve = new PartyParticipant();
      PartyAdmin partyAdmin = new PartyAdmin(partyFactory);

      // Mint dummy NFT to partyAdmin
      DummyERC721 toadz = new DummyERC721();
      toadz.mint(address(partyAdmin));

      (Party party, ,) = partyAdmin.createParty(
        PartyAdmin.PartyCreationMinimalOptions({
          host1: address(partyAdmin),
          host2: address(0),
          passThresholdBps: 5100,
          totalVotingPower: 100,
          preciousTokenAddress: address(toadz),
          preciousTokenId: 1
        })
      );
      // transfer NFT to party
      partyAdmin.transferNft(toadz, 1, address(party));

      partyAdmin.mintGovNft(party, address(john), 50);
      partyAdmin.mintGovNft(party, address(danny), 50);
      partyAdmin.mintGovNft(party, address(steve), 50);

      ListOnZoraProposal.ZoraProposalData memory zpd = ListOnZoraProposal.ZoraProposalData({
        listPrice: 1.5 ether,
        duration: 120,
        token: toadz,
        tokenId: 1
      });

      PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
        maxExecutableTime: uint40(block.timestamp + 10000 hours),
        nonce: 1,
        proposalData: abi.encode(zpd)
      });
      uint256 proposalId = john.makeProposal(party, proposal);

      danny.vote(party, proposalId);
      steve.vote(party, proposalId);

      vm.warp(block.timestamp + 76 hours);

      (PartyGovernance.ProposalState s, ) = party.getProposalStates(proposalId);
      assertEq(uint40(s), uint40(PartyGovernance.ProposalState.Ready));


      // ListOnZoraProposal zp = new ListOnZoraProposal();
      // uint256 proposalId = 

      console.log(proposalId);
      console.log('simple zora 4');
    }
}