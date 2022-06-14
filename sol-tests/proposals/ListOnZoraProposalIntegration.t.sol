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


      console.log('simple zora 2');
    }
}