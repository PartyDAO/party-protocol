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
    assertEq(engInstance.getFlagsForProposalId(1), 0);
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
    assertEq(engInstance.getFlagsForProposalId(1), LibProposal.PROPOSAL_FLAG_UNANIMOUS);
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
      abi.encodeWithSelector(
          PartyGovernance.BadProposalStateError.selector,
          PartyGovernance.ProposalState.Defeated
      )
    );
    john.executeProposal(party, PartyParticipant.ExecutionOptions({
      proposalId: 1,
      proposal: p1,
      preciousTokens: preciousTokens,
      preciousTokenIds: preciousTokenIds,
      progressData: abi.encodePacked([address(0)])
    }));

  }

  function testPartyMemberCannotVoteTwice() public {
    // Create party + mock proposal engine
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

    vm.warp(block.timestamp + 1);

    // Generate and submit proposal
    PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
      maxExecutableTime: 999999999,
      nonce: 1,
      proposalData: abi.encodePacked([0])
    });
    john.makeProposal(party, p1);

    // Vote
    danny.vote(party, 1);

    // Ensure that the same member cannot vote twice
    vm.expectRevert(bytes('ALREADY_VOTED'));
    danny.vote(party, 1);
  }

  // The voting period is over, so the proposal expired without passing
  function testExpiresWithoutPassing() public {
    // Create party
    (Party party, IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) = partyAdmin.createParty(
      partyFactory,
      PartyAdmin.PartyCreationMinimalOptions({
        host1: address(john),
        host2: address(danny),
        passThresholdBps: 5100,
        totalVotingPower: 100,
        preciousTokenAddress: address(toadz),
        preciousTokenId: 1
      })
    );
    DummySimpleProposalEngineImpl propEng = DummySimpleProposalEngineImpl(address(party));

    // Mint governance NFTs
    partyAdmin.mintGovNft(party, address(john), 50);
    partyAdmin.mintGovNft(party, address(danny), 50);

    vm.warp(block.timestamp + 1);

    // Generate proposal
    PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
      maxExecutableTime: 999999999,
      nonce: 1,
      proposalData: abi.encodePacked([0])
    });
    john.makeProposal(party, p1);

    _assertProposalState(party, 1, PartyGovernance.ProposalState.Voting, 50);

    vm.warp(block.timestamp + 98);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Voting, 50);
    
    // ensure defeated
    vm.warp(block.timestamp + 1);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Defeated, 50);

    // ensure can't execute proposal
    vm.expectRevert(
      abi.encodeWithSelector(
          PartyGovernance.BadProposalStateError.selector,
          PartyGovernance.ProposalState.Defeated
      )
    );
    john.executeProposal(party, PartyParticipant.ExecutionOptions({
      proposalId: 1,
      proposal: p1,
      preciousTokens: preciousTokens,
      preciousTokenIds: preciousTokenIds,
      progressData: abi.encodePacked([address(0)])
    }));
  }

  // The proposal passed, but it's now too late to execute because it went over the maxExecutableTime or whatever that variable is called
  function testExpiresWithPassing() public {
    // Create party
    (Party party, IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) = partyAdmin.createParty(
      partyFactory,
      PartyAdmin.PartyCreationMinimalOptions({
        host1: address(john),
        host2: address(danny),
        passThresholdBps: 5100,
        totalVotingPower: 100,
        preciousTokenAddress: address(toadz),
        preciousTokenId: 1
      })
    );
    DummySimpleProposalEngineImpl propEng = DummySimpleProposalEngineImpl(address(party));

    // Mint governance NFTs
    partyAdmin.mintGovNft(party, address(john), 1);
    partyAdmin.mintGovNft(party, address(danny), 50);
    partyAdmin.mintGovNft(party, address(steve), 49);

    vm.warp(block.timestamp + 1);

    // Generate proposal
    PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
      maxExecutableTime: 999999999,
      nonce: 1,
      proposalData: abi.encodePacked([0])
    });
    john.makeProposal(party, p1);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Voting, 1);
    
    danny.vote(party, 1);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Passed, 51);

    vm.warp(block.timestamp + 98);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Passed, 51);

    vm.warp(block.timestamp + 300);
    _assertProposalState(party, 1, PartyGovernance.ProposalState.Ready, 51);

    // warp past maxExecutabletime
    vm.warp(999999999 + 1);

    // ensure can't execute proposal due to maxExecutableTime
    vm.expectRevert(
      abi.encodeWithSelector(
          PartyGovernance.ExecutionTimeExceededError.selector,
          999999999,
          block.timestamp
      )
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
      assertEq(uint256(ps), uint256(expectedProposalState));
      assertEq(pv.votes, expectedNumVotes);
  }

}
