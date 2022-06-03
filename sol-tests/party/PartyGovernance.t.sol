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
  PartyParticipant steve;
  PartyParticipant nicholas;
  DummyERC721 toadz;
  PartyAdmin partyAdmin;

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
    steve = new PartyParticipant();
    nicholas = new PartyParticipant();
    partyAdmin = new PartyAdmin();

    // Mint dummy NFT
    address nftHolderAddress = address(1);
    toadz = new DummyERC721();
    toadz.mint(nftHolderAddress);


  }

  function testSimpleGovernance() public {
    // Create party
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
    partyAdmin.mintGovNft(party, address(john), 49, address(john));
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

  function testSimpleGovernanceUnanimous() public {
    // Create party
    (Party party, IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) = partyAdmin.createParty(
      partyFactory,
      PartyAdmin.PartyCreationMinimalOptions({
        host1: address(this),
        host2: address(0),
        passThresholdBps: 9900,
        totalVotingPower: 100,
        preciousTokenAddress: address(toadz),
        preciousTokenId: 1
      })
    );
    DummySimpleProposalEngineImpl engInstance = DummySimpleProposalEngineImpl(address(party));

    // Mint first governance NFT
    partyAdmin.mintGovNft(party, address(john), 21, address(john));
    assertEq(party.getVotingPowerOfToken(1), 21);
    assertEq(party.ownerOf(1), address(john));
    assertEq(party.getDistributionShareOf(1), 0.21 ether);

    // Increase time and mint another governance NFT
    vm.warp(block.timestamp + 1);
    partyAdmin.mintGovNft(party, address(danny), 22, address(john));
    assertEq(party.getVotingPowerOfToken(2), 22);
    assertEq(party.ownerOf(2), address(danny));
    assertEq(party.getDistributionShareOf(2), 0.22 ether);

    // Increase time and mint another governance NFT
    vm.warp(block.timestamp + 1);
    partyAdmin.mintGovNft(party, address(steve), 28, address(steve));
    assertEq(party.getVotingPowerOfToken(3), 28);
    assertEq(party.ownerOf(3), address(steve));
    assertEq(party.getDistributionShareOf(3), 0.28 ether);

    // Increase time and mint another governance NFT
    vm.warp(block.timestamp + 3);
    partyAdmin.mintGovNft(party, address(nicholas), 29, address(nicholas));
    assertEq(party.getVotingPowerOfToken(4), 29);
    assertEq(party.ownerOf(4), address(nicholas));
    assertEq(party.getDistributionShareOf(4), 0.29 ether);

    // Ensure voting power updated w/ new delegation
    uint40 firstTime = uint40(block.timestamp);
    assertEq(party.getVotingPowerAt(address(john), firstTime), 43);
    assertEq(party.getVotingPowerAt(address(danny), firstTime), 0);
    assertEq(party.getVotingPowerAt(address(steve), firstTime), 28);
    assertEq(party.getVotingPowerAt(address(nicholas), firstTime), 29);

    // Increase time and have danny delegate to self
    uint40 nextTime = firstTime + 10;
    vm.warp(nextTime);
    danny.delegate(party, address(danny));

    // Ensure voting power looks correct for diff times
    assertEq(party.getVotingPowerAt(address(john), firstTime), 43); // stays same for old time
    assertEq(party.getVotingPowerAt(address(danny), firstTime), 0); // stays same for old time
    assertEq(block.timestamp, nextTime);
    assertEq(party.getVotingPowerAt(address(john), nextTime), 21); // diff for new time
    assertEq(party.getVotingPowerAt(address(danny), nextTime), 22); // diff for new time

    // Generate proposal
    PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
      maxExecutableTime: 999999999,
      nonce: 1,
      proposalData: abi.encodePacked([0])
    });
    john.makeProposal(party, p1);

    // Ensure John's votes show up
    assertEq(party.getGovernanceValues().totalVotingPower, 100);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Voting, 21);

    // Danny votes on proposal
    danny.vote(party, 1);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Voting, 43);

    // Steve votes on proposal
    steve.vote(party, 1);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Voting, 71);

    // Nicholas votes on proposal
    nicholas.vote(party, 1);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Passed, 100);

    // Can't execute before execution time passes
    vm.warp(block.timestamp + 299);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Passed, 100);

    // Ensure can execute when exeuctionTime is passed
    vm.warp(block.timestamp + 2);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Ready, 100);
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
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Complete, 100);
    assertEq(engInstance.getLastExecutedProposalId(), 1);
    assertEq(engInstance.getNumExecutedProposals(), 1);
  }

  function testSimpleGovernanceVotingPower() public {
    // Create party
    (Party party, IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) = partyAdmin.createParty(
      partyFactory,
      PartyAdmin.PartyCreationMinimalOptions({
        host1: address(this),
        host2: address(0),
        passThresholdBps: 9900,
        totalVotingPower: 12345,
        preciousTokenAddress: address(toadz),
        preciousTokenId: 1
      })
    );
    DummySimpleProposalEngineImpl engInstance = DummySimpleProposalEngineImpl(address(party));

    // Mint first governance NFT
    partyAdmin.mintGovNft(party, address(john), 12000, address(john));
    assertEq(party.getVotingPowerOfToken(1), 12000);
    assertEq(party.ownerOf(1), address(john));
    assertEq(party.getDistributionShareOf(1), 0.972053462940461725 ether);

    // Increase time and mint another governance NFT
    vm.warp(block.timestamp + 1);
    partyAdmin.mintGovNft(party, address(danny), 193, address(danny));
    assertEq(party.getVotingPowerOfToken(2), 193);
    assertEq(party.ownerOf(2), address(danny));
    assertEq(party.getDistributionShareOf(2), 0.015633859862292426 ether);

    // Increase time and mint another governance NFT
    vm.warp(block.timestamp + 1);
    partyAdmin.mintGovNft(party, address(steve), 7, address(steve));
    assertEq(party.getVotingPowerOfToken(3), 7);
    assertEq(party.ownerOf(3), address(steve));
    assertEq(party.getDistributionShareOf(3), 0.000567031186715269 ether);

    // Increase time and mint another governance NFT
    vm.warp(block.timestamp + 3);
    partyAdmin.mintGovNft(party, address(nicholas), 107, address(nicholas));
    assertEq(party.getVotingPowerOfToken(4), 107);
    assertEq(party.ownerOf(4), address(nicholas));
    assertEq(party.getDistributionShareOf(4), 8667476711219117);

    // Generate proposal
    PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
      maxExecutableTime: 999999999,
      nonce: 1,
      proposalData: abi.encodePacked([0])
    });
    john.makeProposal(party, p1);

    // Ensure John's votes show up
    assertEq(party.getGovernanceValues().totalVotingPower, 12345);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Voting, 12000);

    // Danny votes on proposal
    danny.vote(party, 1);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Voting, 12193);

    // Steve votes on proposal
    steve.vote(party, 1);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Voting, 12200);

    // Nicholas does not vote, and executionTime has passed
    vm.warp(block.timestamp + 500);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Defeated, 12200);

    // Generate new proposal
    PartyGovernance.Proposal memory p2 = PartyGovernance.Proposal({
      maxExecutableTime: 999999999,
      nonce: 2,
      proposalData: abi.encodePacked([0])
    });
    john.makeProposal(party, p2);

    assertEq(party.getGovernanceValues().totalVotingPower, 12345);
    _assertProposalState(party, 2, PartyGovernance.ProposalState.Voting, 12000);

    danny.vote(party, 2);
    _assertProposalState(party, 2, PartyGovernance.ProposalState.Voting, 12193);

    steve.vote(party, 2);
    _assertProposalState(party, 2, PartyGovernance.ProposalState.Voting, 12200);

    // This time, Nicholas votes on proposal
    nicholas.vote(party, 2);
    _assertProposalState(party, 2, PartyGovernance.ProposalState.Voting, 12307);

    // todo: this should be Passed but it is still Voting
    // Can't execute before execution time passes
    vm.warp(block.timestamp + 299);
    _assertProposalState(party, 2, PartyGovernance.ProposalState.Passed, 12307);

    // Nicholas does not vote, and executionTime has passed
    vm.warp(block.timestamp + 500);
    _assertProposalState(party, 2, PartyGovernance.ProposalState.Ready, 12307);

    // // Ensure can execute when exeuctionTime is passed
    // vm.warp(block.timestamp + 2);
    // _assertProposalState(party, 1, PartyGovernance.ProposalState.Ready, 100);
    // assertEq(engInstance.getLastExecutedProposalId(), 0);
    // assertEq(engInstance.getNumExecutedProposals(), 0);

    // Execute proposal
    john.executeProposal(party, PartyParticipant.ExecutionOptions({
      proposalId: 2,
      proposal: p2,
      preciousTokens: preciousTokens,
      preciousTokenIds: preciousTokenIds,
      progressData: abi.encodePacked([address(0)])
    }));

    // Ensure execution occurred
    _assertProposalState(party, 2, PartyGovernance.ProposalState.Complete, 12307);
    assertEq(engInstance.getLastExecutedProposalId(), 2);
    assertEq(engInstance.getNumExecutedProposals(), 1);
  }

  function testVeto() public {
    // Create party
    (Party party, IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) = partyAdmin.createParty(
      partyFactory,
      PartyAdmin.PartyCreationMinimalOptions({
        host1: address(nicholas),
        host2: address(0),
        passThresholdBps: 5100,
        totalVotingPower: 300,
        preciousTokenAddress: address(toadz),
        preciousTokenId: 1
      })
    );
    DummySimpleProposalEngineImpl propEng = DummySimpleProposalEngineImpl(address(party));

    // Mint governance NFTs
    partyAdmin.mintGovNft(party, address(john), 100);
    partyAdmin.mintGovNft(party, address(danny), 50);
    partyAdmin.mintGovNft(party, address(steve), 4);


    vm.warp(block.timestamp + 1);

    // Generate proposal
    PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
      maxExecutableTime: 999999999,
      nonce: 1,
      proposalData: abi.encodePacked([0])
    });
    john.makeProposal(party, p1);
    danny.vote(party, 1);

    _assertProposalState(party, 1, PartyGovernance.ProposalState.Voting, 150);

    steve.vote(party, 1);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Passed, 154);

    // veto
    nicholas.vetoProposal(party, 1);
    // ensure defeated
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Defeated, uint96(int96(-1)));

    // ensure can't execute proposal
    vm.expectRevert(
      abi.encodeWithSignature("BadProposalStateError(uint256)", 2)
    );
    john.executeProposal(party, PartyParticipant.ExecutionOptions({
      proposalId: 1,
      proposal: p1,
      preciousTokens: preciousTokens,
      preciousTokenIds: preciousTokenIds,
      progressData: abi.encodePacked([address(0)])
    }));

  }

  function _assertProposalState(
    Party party,
    uint256 proposalId,
    PartyGovernance.ProposalState expectedProposalState,
    uint96 expectedNumVotes
  ) private {
      (PartyGovernance.ProposalState ps, PartyGovernance.ProposalInfoValues memory pv) = party.getProposalStates(proposalId);
      console.log('');
      console.log('ps',uint256(ps));
      console.log('expectedProposalState', uint256(expectedProposalState));
      assertEq(uint256(ps), uint256(expectedProposalState));
      console.log('pv.votes', pv.votes);
      console.log('expectedNumVotes', expectedNumVotes);
      console.log('');
      assertEq(pv.votes, expectedNumVotes);
  }

}
