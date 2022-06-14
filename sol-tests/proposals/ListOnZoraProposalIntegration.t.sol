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
    // HACK: hardcode the latest Zora auction id. Steps to update:
    //   1. go to the Zora Auction House etherscan page
    //   2. click on the latest "Create Auction" tx
    //   3. click on the "Logs" tab on the tx page
    //   4. cmd + f for "uint256 auctionId"
    uint256 private constant latestZoraAuctionId = 5877;

    error ZoraAuctionIdNotFound();

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

      (Party party, IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) = partyAdmin.createParty(
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


      bytes memory proposalData = abi.encodeWithSelector(
          bytes4(uint32(ProposalExecutionEngine.ProposalType.ListOnZora)),
          zpd
      );

      PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
        maxExecutableTime: uint40(block.timestamp + 10000 hours),
        nonce: 1,
        proposalData: proposalData
      });


      uint256 proposalId = john.makeProposal(party, proposal);

      danny.vote(party, proposalId);
      steve.vote(party, proposalId);

      vm.warp(block.timestamp + 76 hours);

      (PartyGovernance.ProposalState s, ) = party.getProposalStates(proposalId);
      assertEq(uint40(s), uint40(PartyGovernance.ProposalState.Ready));

      PartyParticipant.ExecutionOptions memory eo = PartyParticipant.ExecutionOptions({
        proposalId: proposalId,
        proposal: proposal,
        preciousTokens: preciousTokens,
        preciousTokenIds: preciousTokenIds,
        progressData: ''
      });

      john.executeProposal(party, eo);

      assertEq(toadz.ownerOf(1), address(ZORA));

      // start at the latest known zora auction id and loop forward to find the auction id
      // for the auction created by the proposal
      uint256 proposalAuctionId;
      for (uint256 i = 1; i <= 10; ++i) {
        uint256 currAuctionId = latestZoraAuctionId + i;
        address currAuctionTokenAddress = address(ZORA.auctions(currAuctionId).tokenContract);
        uint256 currAuctionTokenId = ZORA.auctions(currAuctionId).tokenId;

        if (currAuctionTokenAddress == address(toadz) && currAuctionTokenId == 1) {
          // we have found our auction id
          proposalAuctionId = currAuctionId;
          break;
        }
      }

      if (proposalAuctionId == 0) {
        revert ZoraAuctionIdNotFound();
      }

      console.log('proposalAuctionId', proposalAuctionId);

      // bid up zora auction

      // have zora auction finish

      // finalize zora auction

      // ensure ETH is held by party

      // distribute ETH and claim distributions

    }
}
