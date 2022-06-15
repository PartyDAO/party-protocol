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
    //     https://etherscan.io/address/0xE468cE99444174Bd3bBBEd09209577d25D1ad673
    //   2. click on the latest "Create Auction" tx
    //   3. click on the "Logs" tab on the tx page
    //   4. cmd + f for "uint256 auctionId"
    uint256 private constant latestZoraAuctionId = 5879;
    IERC20 private constant ETH_TOKEN = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    GlobalsAdmin globalsAdmin;
    Globals globals;
    Party partyImpl;
    TokenDistributor tokenDistributor;
    IWyvernExchangeV2 wyvern;
    SharedWyvernV2Maker wyvernMaker;
    ProposalExecutionEngine pe;
    PartyFactory partyFactory;
    address johnAddress;
    address dannyAddress;
    address steveAddress;

    error ZoraAuctionIdNotFound();

    constructor() ZoraTestUtils(ZORA) {}

    function setUp() public onlyForked {
      globalsAdmin = new GlobalsAdmin();
      globals = globalsAdmin.globals();
      partyImpl = new Party(globals);
      globalsAdmin.setPartyImpl(address(partyImpl));
      address globalDaoWalletAddress = address(420);
      globalsAdmin.setGlobalDaoWallet(globalDaoWalletAddress);

      tokenDistributor = new TokenDistributor(globals);
      globalsAdmin.setTokenDistributor(address(tokenDistributor));

      wyvern = IWyvernExchangeV2(address(0x7f268357A8c2552623316e2562D90e642bB538E5));
      wyvernMaker = new SharedWyvernV2Maker(wyvern);
      pe = new ProposalExecutionEngine(globals, wyvernMaker, ZORA);
      globalsAdmin.setProposalEng(address(pe));

      partyFactory = new PartyFactory(globals);

      johnAddress = 0x0000000000000000000000000000000000000000;
      dannyAddress = 0x0000000000000000000000000000000000000000;
      steveAddress = 0x0000000000000000000000000000000000000000;
    }

    function testSimpleZora() public onlyForked {
      PartyParticipant john = new PartyParticipant();
      PartyParticipant danny = new PartyParticipant();
      PartyParticipant steve = new PartyParticipant();
      PartyAdmin partyAdmin = new PartyAdmin(partyFactory);

      johnAddress = address(john);
      dannyAddress = address(danny);
      steveAddress = address(steve);

      // Mint dummy NFT to partyAdmin
      DummyERC721 toadz = new DummyERC721();
      toadz.mint(address(partyAdmin));

      (Party party, IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) = partyAdmin.createParty(
        PartyAdmin.PartyCreationMinimalOptions({
          host1: address(partyAdmin),
          host2: address(0),
          passThresholdBps: 5100,
          totalVotingPower: 150,
          preciousTokenAddress: address(toadz),
          preciousTokenId: 1
        })
      );
      // transfer NFT to party
      partyAdmin.transferNft(toadz, 1, address(party));

      partyAdmin.mintGovNft(party, johnAddress, 50);
      partyAdmin.mintGovNft(party, dannyAddress, 50);
      partyAdmin.mintGovNft(party, steveAddress, 50);

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
      for (uint256 i = 1; i <= 500; ++i) {
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

      // zora auction lifecycle tests
      {
        // bid up zora auction
        address auctionFinalizer = 0x000000000000000000000000000000000000dEaD;
        address auctionWinner = 0x000000000000000000000000000000000000D00d;
        _bidOnZoraListing(proposalAuctionId, auctionFinalizer, 1.6 ether);
        _bidOnZoraListing(proposalAuctionId, 0x0000000000000000000000000000000000001337, 4.2 ether);
        _bidOnZoraListing(proposalAuctionId, auctionWinner, 13.37 ether);

        // have zora auction finish
        // TODO: i tried +120, and +121 and the test failed with error "Reason: Auction hasn't completed"
        vm.warp(block.timestamp + 1000000000000);

        // finalize zora auction
        ZORA.endAuction(proposalAuctionId);

        // ensure ETH is held by party
        assertEq(toadz.ownerOf(1), auctionWinner);
      }

      assertEq(address(party).balance, 13.37 ether);

      // distribute ETH and claim distributions
      {
        vm.prank(johnAddress);
        TokenDistributor.DistributionInfo memory distributionInfo = john.distributeEth(party, ETH_TOKEN);

        uint256 johnPrevBalance = johnAddress.balance;
        vm.prank(johnAddress);
        tokenDistributor.claim(distributionInfo, 1);
        assertEq(johnAddress.balance, (4.456666666666666662 ether) + johnPrevBalance);

        uint256 dannyPrevBalance = dannyAddress.balance;
        vm.prank(dannyAddress);
        tokenDistributor.claim(distributionInfo, 2);
        assertEq(dannyAddress.balance, (4.456666666666666662 ether) + dannyPrevBalance);

        uint256 stevePrevBalance = steveAddress.balance;
        vm.prank(steveAddress);
        tokenDistributor.claim(distributionInfo, 3);
        assertEq(steveAddress.balance, (4.456666666666666662 ether) + stevePrevBalance);
      }
    }
}
