// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/party/PartyFactory.sol";
import "../../contracts/party/Party.sol";
import "../../contracts/globals/Globals.sol";
import "../proposals/TestableProposalExecutionEngine.sol";
import "../proposals/DummyProposalEngineImpl.sol";
import "../TestUtils.sol";
import "../DummyERC721.sol";

contract PartyGovernanceTest is Test,TestUtils {
  Globals globals;
  address immutable GLOBALS_ADMIN = address(99);
  PartyFactory partyFactory;

  function setUp() public {
    vm.deal(GLOBALS_ADMIN, 100 ether);
    globals = new Globals(GLOBALS_ADMIN);

    DummyProposalEngineImpl newEngImpl = new DummyProposalEngineImpl();

    Party partyImpl = new Party(globals);
    vm.startPrank(GLOBALS_ADMIN);
    globals.setAddress(
        LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL,
        // We will test upgrades to this impl.
        address(newEngImpl)
    );
    globals.setAddress(
      LibGlobals.GLOBAL_PARTY_IMPL,
      address(partyImpl)
    );
    vm.stopPrank();

    partyFactory = new PartyFactory(globals);

    // TestableProposalExecutionEngine eng = new TestableProposalExecutionEngine(
    //         globals,
    //         SharedWyvernV2Maker(_randomAddress()),
    //         IZoraAuctionHouse(_randomAddress())
    //     );

  }

  function testSimpleGovernance() public {
    vm.deal(address(1), 100 ether);
    vm.startPrank(address(1));

    address[] memory hosts = new address[](2);
    hosts[0] = address(2);
    hosts[1] = address(1);

    PartyGovernance.GovernanceOpts memory govOpts = PartyGovernance.GovernanceOpts({
      hosts: hosts,
      voteDuration: 99,
      executionDelay: 300,
      passThresholdBps: 51,
      totalVotingPower: 100
    });
    Party.PartyOptions memory po = Party.PartyOptions({
      governance: govOpts,
      name: 'Dope party',
      symbol: 'DOPE'
    });

    DummyERC721 dummyErc721 = new DummyERC721();
    dummyErc721.mint(address(1));

    IERC721[] memory preciousTokens = new IERC721[](1);
    preciousTokens[0] = IERC721(address(dummyErc721));

    uint256[] memory preciousTokenIds = new uint256[](1);
    preciousTokenIds[0] = 1;

    Party party = partyFactory.createParty(
      address(1),
      po,
      preciousTokens,
      preciousTokenIds
    );
    party.mint(
      address(3),
      49,
      address(3)
    );
    assertEq(party.getVotingPowerOfToken(1), 49);
    assertEq(party.ownerOf(1), address(3));
    assertEq(party.getDistributionShareOf(1), 0.49 ether);

    vm.warp(block.timestamp + 1);
    party.mint(
      address(4),
      10,
      address(3)
    );
    assertEq(party.getVotingPowerOfToken(2), 10);
    assertEq(party.ownerOf(2), address(4));
    assertEq(party.getDistributionShareOf(2), 0.10 ether);

    uint40 firstTime = uint40(block.timestamp);

    assertEq(party.getVotingPowerAt(address(3), firstTime), 59);
    assertEq(party.getVotingPowerAt(address(4), firstTime), 0);

    uint40 nextTime = firstTime + 10;
    vm.warp(nextTime);
    vm.stopPrank();
    vm.prank(address(4));
    party.delegateVotingPower(address(4));

    assertEq(party.getVotingPowerAt(address(3), firstTime), 59); // stays same for old time
    assertEq(party.getVotingPowerAt(address(4), firstTime), 0); // stays same for old time
    assertEq(block.timestamp, nextTime);
    assertEq(party.getVotingPowerAt(address(3), nextTime), 49); // diff for new time
    assertEq(party.getVotingPowerAt(address(4), nextTime), 10); // diff for new time
  }
}