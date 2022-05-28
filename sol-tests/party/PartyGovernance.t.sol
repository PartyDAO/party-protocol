// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/party/PartyFactory.sol";
import "../../contracts/party/Party.sol";
import "../../contracts/globals/Globals.sol";
import "../proposals/DummySimpleProposalEngineImpl.sol";
import "../proposals/DummyProposalEngineImpl.sol";
import "../TestUtils.sol";
import "../DummyERC721.sol";
import "../TestUsers.sol";

contract PartyGovernanceTest is Test, TestUtils {
  PartyFactory partyFactory;
  DummySimpleProposalEngineImpl eng;
  PartyParticipant john;
  PartyParticipant danny;
  DummyERC721 toadz;

  function setUp() public {
    GlobalsAdmin globalsAdmin = new GlobalsAdmin();
    Globals globals = globalsAdmin.globals();
  
    Party partyImpl = new Party(globals);
    globalsAdmin.setPartyImpl(address(partyImpl));

    eng = new DummySimpleProposalEngineImpl();
    globalsAdmin.setProposalEng(address(eng));
  
    partyFactory = new PartyFactory(globals);

    john = new PartyParticipant();
    danny = new PartyParticipant();

    // Mint dummy NFT
    address nftHolderAddress = address(1);
    toadz = new DummyERC721();
    toadz.mint(nftHolderAddress);

  }

  function testSimpleGovernance() public {
    // Create party
    PartyAdmin partyAdmin = new PartyAdmin();
    (Party party, IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) = partyAdmin.createParty(
      partyFactory,
      PartyAdmin.PartyCreationMinimalOptions({
        host1: address(this),
        host2: address(0),
        passThresholdBps: 5100,
        totalVotingPower: 100,
        preciousTokenAddress: address(toadz),
        preciousTokenId: 1
      })
    );
    DummySimpleProposalEngineImpl engInstance = DummySimpleProposalEngineImpl(address(party));

    // Mint first governance NFT
    partyAdmin.mintGovNft(party, address(john), 49,address(john));
    assertEq(party.getVotingPowerOfToken(1), 49);
    assertEq(party.ownerOf(1), address(john));
    assertEq(party.getDistributionShareOf(1), 0.49 ether);

    // Increase time and mint another governance NFT
    vm.warp(block.timestamp + 1);
    partyAdmin.mintGovNft(party, address(danny), 10, address(john));
    assertEq(party.getVotingPowerOfToken(2), 10);
    assertEq(party.ownerOf(2), address(danny));
    assertEq(party.getDistributionShareOf(2), 0.10 ether);

    // Ensure voting power updated w/ new delegation
    uint40 firstTime = uint40(block.timestamp);
    assertEq(party.getVotingPowerAt(address(john), firstTime), 59);
    assertEq(party.getVotingPowerAt(address(danny), firstTime), 0);

    // Increase time and have danny delegate to self
    uint40 nextTime = firstTime + 10;
    vm.warp(nextTime);
    danny.delegate(party, address(danny));

    // Ensure voting power looks correct for diff times
    assertEq(party.getVotingPowerAt(address(john), firstTime), 59); // stays same for old time
    assertEq(party.getVotingPowerAt(address(danny), firstTime), 0); // stays same for old time
    assertEq(block.timestamp, nextTime);
    assertEq(party.getVotingPowerAt(address(john), nextTime), 49); // diff for new time
    assertEq(party.getVotingPowerAt(address(danny), nextTime), 10); // diff for new time

    // Generate proposal
    PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
      maxExecutableTime: 999999999,
      nonce: 1,
      proposalData: abi.encodePacked([0])
    });
    john.makeProposal(party, p1);

    // Ensure John's votes show up
    assertEq(party.getGovernanceValues().totalVotingPower, 100);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Voting, 49);

    // Danny votes on proposal
    danny.vote(party, 1);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Passed, 59);

    // Can't execute before execution time passes
    vm.warp(block.timestamp + 299);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Passed, 59);

    // Ensure can execute when exeuctionTime is passed
    vm.warp(block.timestamp + 2);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Ready, 59);
    assertEq(engInstance.getLastExecutedProposalId(), 0);
    assertEq(engInstance.getNumExecutedProposals(), 0);

    // Execute proposal
    john.executeProposal(party, PartyParticipant.ExecutionOptions({
      proposalId: 1,
      proposal: p1,
      preciousTokens: preciousTokens,
      preciousTokenIds: preciousTokenIds,
      progressData: abi.encodePacked([address(0)])
    }));

    // Ensure execution occurred
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Complete, 59);
    assertEq(engInstance.getLastExecutedProposalId(), 1);
    assertEq(engInstance.getNumExecutedProposals(), 1);
  }

  function testVeto() public {

  }

  function _assertProposalState(
    Party party,
    uint256 proposalId,
    PartyGovernance.ProposalState expectedProposalState,
    uint256 expectedNumVotes
  ) private {
      (PartyGovernance.ProposalState ps, PartyGovernance.ProposalInfoValues memory pv) = party.getProposalStates(proposalId);
      assert(ps == expectedProposalState);
      assertEq(pv.votes, expectedNumVotes);
  }

}

