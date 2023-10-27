// SPDX-License-Identifier: UNLICENSED
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
    Party partyImpl;
    PartyFactory partyFactory;
    DummySimpleProposalEngineImpl eng;
    PartyParticipant john;
    PartyParticipant danny;
    PartyParticipant steve;
    PartyParticipant nicholas;
    DummyERC721 toadz;
    PartyAdmin partyAdmin;
    address globalDaoWalletAddress = address(420);

    event PartyDelegateUpdated(address indexed owner, address indexed delegate);
    event PartyCardIntrinsicVotingPowerSet(uint256 indexed tokenId, uint256 intrinsicVotingPower);
    event PartyVotingSnapshotCreated(
        address indexed voter,
        uint40 timestamp,
        uint96 delegatedVotingPower,
        uint96 intrinsicVotingPower,
        bool isDelegated
    );

    function setUp() public {
        GlobalsAdmin globalsAdmin = new GlobalsAdmin();
        Globals globals = globalsAdmin.globals();
        partyImpl = new Party(globals);
        globalsAdmin.setGlobalDaoWallet(globalDaoWalletAddress);

        eng = new DummySimpleProposalEngineImpl();
        globalsAdmin.setProposalEng(address(eng));

        partyFactory = new PartyFactory(globals);

        john = new PartyParticipant();
        danny = new PartyParticipant();
        steve = new PartyParticipant();
        nicholas = new PartyParticipant();
        partyAdmin = new PartyAdmin(partyFactory);

        // Mint dummy NFT
        address nftHolderAddress = address(1);
        toadz = new DummyERC721();
        toadz.mint(nftHolderAddress);
    }

    /// @notice Create a simple party and ensure proposals work.
    function testGovernance() public {
        // Create party
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(this),
                    host2: address(0),
                    passThresholdBps: 5100,
                    totalVotingPower: 100,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );
        DummySimpleProposalEngineImpl engInstance = DummySimpleProposalEngineImpl(address(party));

        // Mint first governance NFT
        vm.expectEmit(true, true, true, true);
        emit PartyCardIntrinsicVotingPowerSet(1, 49);
        vm.expectEmit(true, true, true, true);
        emit PartyVotingSnapshotCreated(address(john), uint40(block.timestamp), 0, 49, false);

        partyAdmin.mintGovNft(party, address(john), 49, address(john));
        assertEq(party.votingPowerByTokenId(1), 49);
        assertEq(party.ownerOf(1), address(john));

        // Increase time and mint another governance NFT
        vm.warp(block.timestamp + 1);
        partyAdmin.mintGovNft(party, address(danny), 10, address(john));
        assertEq(party.votingPowerByTokenId(2), 10);
        assertEq(party.ownerOf(2), address(danny));

        // Ensure voting power updated w/ new delegation
        uint40 firstTime = uint40(block.timestamp);
        assertEq(party.getVotingPowerAt(address(john), firstTime, 1), 59);
        assertEq(party.getVotingPowerAt(address(danny), firstTime, 0), 0);

        // Increase time and have danny delegate to self
        uint40 nextTime = firstTime + 10;
        vm.warp(nextTime);
        vm.expectEmit(true, true, true, true);
        emit PartyDelegateUpdated(address(danny), address(danny));
        danny.delegate(party, address(danny));

        // Ensure voting power looks correct for diff times
        assertEq(party.getVotingPowerAt(address(john), firstTime, 1), 59); // stays same for old time
        assertEq(party.getVotingPowerAt(address(danny), firstTime, 0), 0); // stays same for old time
        assertEq(block.timestamp, nextTime);
        assertEq(party.getVotingPowerAt(address(john), nextTime, 2), 49); // diff for new time
        assertEq(party.getVotingPowerAt(address(danny), nextTime, 1), 10); // diff for new time

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });
        john.makeProposal(party, p1, 2);

        // Ensure John's votes show up
        assertEq(party.getGovernanceValues().totalVotingPower, 100);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Voting, 49);

        // Danny votes on proposal
        danny.vote(party, 1, 1);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Passed, 59);

        // Can't execute before execution time passes
        vm.warp(block.timestamp + 299);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Passed, 59);

        // Ensure can execute when executionTime is passed
        vm.warp(block.timestamp + 2);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Ready, 59);
        assertEq(engInstance.getLastExecutedProposalId(), 0);
        assertEq(engInstance.getNumExecutedProposals(), 0);

        // Execute proposal
        john.executeProposal(
            party,
            PartyParticipant.ExecutionOptions({
                proposalId: 1,
                proposal: p1,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds,
                progressData: abi.encodePacked([address(0)])
            })
        );

        // Ensure execution occurred
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Complete, 59);
        assertEq(engInstance.getLastExecutedProposalId(), 1);
        assertEq(engInstance.getNumExecutedProposals(), 1);
        assertEq(engInstance.getFlagsForProposalId(1), 0);

        vm.expectEmit(true, true, true, true);
        emit PartyDelegateUpdated(address(danny), address(10));
        danny.delegate(party, address(10));
    }

    function testVotingSnapshot_emittedWhenOverwritenSameBlock() public {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 100,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        // Mint first governance NFT
        vm.expectEmit(true, true, true, true);
        emit PartyCardIntrinsicVotingPowerSet(1, 49);
        vm.expectEmit(true, true, true, true);
        emit PartyVotingSnapshotCreated(address(john), uint40(block.timestamp), 0, 49, false);
        partyAdmin.mintGovNft(party, address(john), 49, address(john));

        vm.expectEmit(true, true, true, true);
        emit PartyCardIntrinsicVotingPowerSet(2, 20);
        vm.expectEmit(true, true, true, true);
        emit PartyVotingSnapshotCreated(address(john), uint40(block.timestamp), 0, 69, false);
        partyAdmin.mintGovNft(party, address(john), 20, address(john));
    }

    /// @notice A unanimous proposal skips the execution delay and returns the unanimous flag
    function testGovernance_Unanimous() public {
        // Create party
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(this),
                    host2: address(0),
                    passThresholdBps: 9900,
                    totalVotingPower: 100,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );
        DummySimpleProposalEngineImpl engInstance = DummySimpleProposalEngineImpl(address(party));

        // Mint first governance NFT
        partyAdmin.mintGovNft(party, address(john), 21, address(john));
        assertEq(party.votingPowerByTokenId(1), 21);
        assertEq(party.ownerOf(1), address(john));

        // Increase time and mint another governance NFT
        vm.warp(block.timestamp + 1);
        partyAdmin.mintGovNft(party, address(danny), 22, address(john));
        assertEq(party.votingPowerByTokenId(2), 22);
        assertEq(party.ownerOf(2), address(danny));

        // Increase time and mint another governance NFT
        vm.warp(block.timestamp + 1);
        partyAdmin.mintGovNft(party, address(steve), 28, address(steve));
        assertEq(party.votingPowerByTokenId(3), 28);
        assertEq(party.ownerOf(3), address(steve));

        // Increase time and mint another governance NFT
        vm.warp(block.timestamp + 3);
        partyAdmin.mintGovNft(party, address(nicholas), 29, address(nicholas));
        assertEq(party.votingPowerByTokenId(4), 29);
        assertEq(party.ownerOf(4), address(nicholas));

        // Ensure voting power updated w/ new delegation
        uint40 firstTime = uint40(block.timestamp);
        assertEq(party.getVotingPowerAt(address(john), firstTime, 1), 43);
        assertEq(party.getVotingPowerAt(address(danny), firstTime, 0), 0);
        assertEq(party.getVotingPowerAt(address(steve), firstTime, 0), 28);
        assertEq(party.getVotingPowerAt(address(nicholas), firstTime, 0), 29);

        // Increase time and have danny delegate to self
        uint40 nextTime = firstTime + 10;
        vm.warp(nextTime);
        danny.delegate(party, address(danny));

        // Ensure voting power looks correct for diff times
        assertEq(party.getVotingPowerAt(address(john), firstTime, 1), 43); // stays same for old time
        assertEq(party.getVotingPowerAt(address(danny), firstTime, 0), 0); // stays same for old time
        assertEq(block.timestamp, nextTime);
        assertEq(party.getVotingPowerAt(address(john), nextTime, 2), 21); // diff for new time
        assertEq(party.getVotingPowerAt(address(danny), nextTime, 1), 22); // diff for new time

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });
        john.makeProposal(party, p1, 2);

        // Ensure John's votes show up
        assertEq(party.getGovernanceValues().totalVotingPower, 100);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Voting, 21);

        // Danny votes on proposal
        danny.vote(party, 1, 1);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Voting, 43);

        // Steve votes on proposal
        steve.vote(party, 1, 0);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Voting, 71);

        // Nicholas votes on proposal
        nicholas.vote(party, 1, 0);

        // Unanimous so can execute immediately.
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Ready, 100);
        assertEq(engInstance.getLastExecutedProposalId(), 0);
        assertEq(engInstance.getNumExecutedProposals(), 0);

        // Execute proposal
        john.executeProposal(
            party,
            PartyParticipant.ExecutionOptions({
                proposalId: 1,
                proposal: p1,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds,
                progressData: abi.encodePacked([address(0)])
            })
        );

        // Ensure execution occurred
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Complete, 100);
        assertEq(engInstance.getLastExecutedProposalId(), 1);
        assertEq(engInstance.getNumExecutedProposals(), 1);
        assertEq(engInstance.getFlagsForProposalId(1), LibProposal.PROPOSAL_FLAG_UNANIMOUS);
    }

    /// @notice When all hosts accept a proposal, execution delay is bypassed and the
    ///         `PROPOSAL_FLAG_HOSTS_ACCEPT` flag is returned.
    function testGovernance_allHostsAccept() public {
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(danny),
                    host2: address(this),
                    passThresholdBps: 5000,
                    totalVotingPower: 60,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );
        DummySimpleProposalEngineImpl engInstance = DummySimpleProposalEngineImpl(address(party));

        // Mint first governance NFT
        partyAdmin.mintGovNft(party, address(john), 20, address(john));
        assertEq(party.votingPowerByTokenId(1), 20);
        assertEq(party.ownerOf(1), address(john));

        // mint another governance NFT
        partyAdmin.mintGovNft(party, address(danny), 20, address(danny));
        assertEq(party.votingPowerByTokenId(2), 20);
        assertEq(party.ownerOf(2), address(danny));

        // mint third governance NFT
        partyAdmin.mintGovNft(party, address(steve), 20, address(steve));
        assertEq(party.votingPowerByTokenId(3), 20);
        assertEq(party.ownerOf(3), address(steve));

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });
        john.makeProposal(party, p1, 2);

        // Ensure John's votes show up
        assertEq(party.getGovernanceValues().totalVotingPower, 60);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Voting, 20);

        danny.vote(party, 1, 0);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Passed, 40);

        party.accept(1, 0);

        // Host accepted so can execute immediately.
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Ready, 40);
        assertEq(engInstance.getLastExecutedProposalId(), 0);
        assertEq(engInstance.getNumExecutedProposals(), 0);

        // Execute proposal
        john.executeProposal(
            party,
            PartyParticipant.ExecutionOptions({
                proposalId: 1,
                proposal: p1,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds,
                progressData: abi.encodePacked([address(0)])
            })
        );

        // Ensure execution occurred
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Complete, 40);
        assertEq(engInstance.getFlagsForProposalId(1), LibProposal.PROPOSAL_FLAG_HOSTS_ACCEPT);
        assertEq(engInstance.getLastExecutedProposalId(), 1);
        assertEq(engInstance.getNumExecutedProposals(), 1);
    }

    /// @notice Even if a host has no voting power, their acceptance allows bypassing veto period
    function testGovernance_allHostsAccept_noHostVotes() public {
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(this),
                    host2: address(0),
                    passThresholdBps: 5000,
                    totalVotingPower: 43,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );
        DummySimpleProposalEngineImpl engInstance = DummySimpleProposalEngineImpl(address(party));

        // Mint first governance NFT
        partyAdmin.mintGovNft(party, address(john), 22, address(john));
        assertEq(party.votingPowerByTokenId(1), 22);
        assertEq(party.ownerOf(1), address(john));

        // mint another governance NFT
        partyAdmin.mintGovNft(party, address(danny), 21, address(danny));
        assertEq(party.votingPowerByTokenId(2), 21);
        assertEq(party.ownerOf(2), address(danny));

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });
        john.makeProposal(party, p1, 2);

        // Ensure John's votes show up
        assertEq(party.getGovernanceValues().totalVotingPower, 43);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Passed, 22);

        party.accept(1, 0);

        // Host accepted so can execute immediately.
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Ready, 22);
        assertEq(engInstance.getLastExecutedProposalId(), 0);
        assertEq(engInstance.getNumExecutedProposals(), 0);

        // Execute proposal
        john.executeProposal(
            party,
            PartyParticipant.ExecutionOptions({
                proposalId: 1,
                proposal: p1,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds,
                progressData: abi.encodePacked([address(0)])
            })
        );

        // Ensure execution occurred
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Complete, 22);
        assertEq(engInstance.getLastExecutedProposalId(), 1);
        assertEq(engInstance.getNumExecutedProposals(), 1);
    }

    /// @notice If a host accepts, then abdicates host status, all other hosts still
    ///         need to accept before skipping veto period
    function testGovernance_allHostsAccept_abdicateHost() public {
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(this),
                    host2: address(steve),
                    passThresholdBps: 5000,
                    totalVotingPower: 43,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );
        DummySimpleProposalEngineImpl engInstance = DummySimpleProposalEngineImpl(address(party));

        // Mint first governance NFT
        partyAdmin.mintGovNft(party, address(john), 22, address(john));
        assertEq(party.votingPowerByTokenId(1), 22);
        assertEq(party.ownerOf(1), address(john));

        // mint another governance NFT
        partyAdmin.mintGovNft(party, address(danny), 21, address(danny));
        assertEq(party.votingPowerByTokenId(2), 21);
        assertEq(party.ownerOf(2), address(danny));

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });
        john.makeProposal(party, p1, 2);

        party.accept(1, 0);

        // Remove second host
        party.abdicateHost(address(0));
        assertEq(party.numHosts(), 1);

        // Still need to wait for the second host
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Passed, 22);

        // Votes from the only host
        steve.vote(party, 1, 0);

        // Host accepted so can execute immediately.
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Ready, 22);
        assertEq(engInstance.getLastExecutedProposalId(), 0);
        assertEq(engInstance.getNumExecutedProposals(), 0);

        // Execute proposal
        john.executeProposal(
            party,
            PartyParticipant.ExecutionOptions({
                proposalId: 1,
                proposal: p1,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds,
                progressData: abi.encodePacked([address(0)])
            })
        );

        // Ensure execution occurred
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Complete, 22);
        assertEq(engInstance.getFlagsForProposalId(1), LibProposal.PROPOSAL_FLAG_HOSTS_ACCEPT);
        assertEq(engInstance.getLastExecutedProposalId(), 1);
        assertEq(engInstance.getNumExecutedProposals(), 1);
    }

    /// @notice Ensure both flags are passed for unanimous and hosts accept proposal
    function testGovernance_allHostsAccept_andUnanimous() public {
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(danny),
                    host2: address(0),
                    passThresholdBps: 6000,
                    totalVotingPower: 40,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );
        DummySimpleProposalEngineImpl engInstance = DummySimpleProposalEngineImpl(address(party));

        // Mint first governance NFT
        partyAdmin.mintGovNft(party, address(john), 20, address(john));
        assertEq(party.votingPowerByTokenId(1), 20);
        assertEq(party.ownerOf(1), address(john));

        // mint another governance NFT
        partyAdmin.mintGovNft(party, address(danny), 20, address(danny));
        assertEq(party.votingPowerByTokenId(2), 20);
        assertEq(party.ownerOf(2), address(danny));

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });
        john.makeProposal(party, p1, 2);

        // Ensure John's votes show up
        assertEq(party.getGovernanceValues().totalVotingPower, 40);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Voting, 20);

        danny.vote(party, 1, 0);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Ready, 40);
        assertEq(engInstance.getLastExecutedProposalId(), 0);
        assertEq(engInstance.getNumExecutedProposals(), 0);

        // Execute proposal
        john.executeProposal(
            party,
            PartyParticipant.ExecutionOptions({
                proposalId: 1,
                proposal: p1,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds,
                progressData: abi.encodePacked([address(0)])
            })
        );

        // Ensure execution occurred
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Complete, 40);
        assertEq(
            engInstance.getFlagsForProposalId(1),
            LibProposal.PROPOSAL_FLAG_HOSTS_ACCEPT | LibProposal.PROPOSAL_FLAG_UNANIMOUS
        );
        assertEq(engInstance.getLastExecutedProposalId(), 1);
        assertEq(engInstance.getNumExecutedProposals(), 1);
    }

    /// @notice Ensure veto period enforced when no hosts
    function testGovernance_allHostsAccept_noHostsVetoPeriod() public {
        // When all hosts accept a proposal, execution delay is bypassed
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(0),
                    host2: address(0),
                    passThresholdBps: 5000,
                    totalVotingPower: 43,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );

        // Mint first governance NFT
        partyAdmin.mintGovNft(party, address(john), 22, address(john));
        assertEq(party.votingPowerByTokenId(1), 22);
        assertEq(party.ownerOf(1), address(john));

        // mint another governance NFT
        partyAdmin.mintGovNft(party, address(danny), 21, address(danny));
        assertEq(party.votingPowerByTokenId(2), 21);
        assertEq(party.ownerOf(2), address(danny));

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });
        john.makeProposal(party, p1, 2);

        // Ensure John's votes show up
        assertEq(party.getGovernanceValues().totalVotingPower, 43);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Passed, 22);

        // No hosts, must wait delay
        vm.warp(block.timestamp + 300);

        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Ready, 22);

        // Execute proposal
        john.executeProposal(
            party,
            PartyParticipant.ExecutionOptions({
                proposalId: 1,
                proposal: p1,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds,
                progressData: abi.encodePacked([address(0)])
            })
        );
    }

    function testGovernance_veto() public {
        // Create party
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(nicholas),
                    host2: address(0),
                    passThresholdBps: 5100,
                    totalVotingPower: 300,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );

        // Mint governance NFTs
        partyAdmin.mintGovNft(party, address(john), 100);
        partyAdmin.mintGovNft(party, address(danny), 50);
        partyAdmin.mintGovNft(party, address(steve), 4);

        vm.warp(block.timestamp + 1);

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });
        john.makeProposal(party, p1, 0);
        danny.vote(party, 1, 0);

        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Voting, 150);

        steve.vote(party, 1, 0);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Passed, 154);

        // veto
        nicholas.vetoProposal(party, 1);
        // ensure defeated
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Defeated, uint96(int96(-1)));

        // ensure can't execute proposal
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Defeated
            )
        );
        john.executeProposal(
            party,
            PartyParticipant.ExecutionOptions({
                proposalId: 1,
                proposal: p1,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds,
                progressData: abi.encodePacked([address(0)])
            })
        );
    }

    function testGovernance_veto_statusReady() public {
        // Create party
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(nicholas),
                    host2: address(0),
                    passThresholdBps: 5100,
                    totalVotingPower: 300,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );

        // Mint governance NFTs
        partyAdmin.mintGovNft(party, address(john), 100);
        partyAdmin.mintGovNft(party, address(danny), 50);
        partyAdmin.mintGovNft(party, address(steve), 4);

        vm.warp(block.timestamp + 1);

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });
        john.makeProposal(party, p1, 0);
        danny.vote(party, 1, 0);

        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Voting, 150);

        steve.vote(party, 1, 0);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Passed, 154);

        vm.warp(block.timestamp + party.getGovernanceValues().executionDelay);

        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Ready, 154);

        // veto
        nicholas.vetoProposal(party, 1);
        // ensure defeated
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Defeated, uint96(int96(-1)));
    }

    function testGovernance_veto_invalidProposalStatus() public {
        // Create party
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(nicholas),
                    host2: address(0),
                    passThresholdBps: 5100,
                    totalVotingPower: 300,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );

        // Mint governance NFTs
        partyAdmin.mintGovNft(party, address(john), 100);
        partyAdmin.mintGovNft(party, address(danny), 50);
        partyAdmin.mintGovNft(party, address(steve), 4);

        vm.warp(block.timestamp + 1);

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });
        john.makeProposal(party, p1, 0);
        danny.vote(party, 1, 0);

        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Voting, 150);

        steve.vote(party, 1, 0);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Passed, 154);

        vm.warp(block.timestamp + party.getGovernanceValues().executionDelay);

        john.executeProposal(
            party,
            PartyParticipant.ExecutionOptions({
                proposalId: 1,
                proposal: p1,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds,
                progressData: abi.encodePacked([address(0)])
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Complete
            )
        );
        nicholas.vetoProposal(party, 1);
    }

    function testGovernance_vote_cannotVoteTwice() public {
        // Create party + mock proposal engine
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(nicholas),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 300,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        // Mint governance NFTs
        partyAdmin.mintGovNft(party, address(john), 100);
        partyAdmin.mintGovNft(party, address(danny), 50);

        vm.warp(block.timestamp + 1);

        // Generate and submit proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });
        john.makeProposal(party, p1, 0);

        // Vote
        danny.vote(party, 1, 0);

        // Ensure that the same member cannot vote twice
        vm.expectRevert(
            abi.encodeWithSelector(PartyGovernance.AlreadyVotedError.selector, address(danny))
        );
        danny.vote(party, 1, 0);
    }

    // The voting period is over, so the proposal expired without passing
    function testGovernance_proposalStatus_expired() public {
        // Create party
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(john),
                    host2: address(danny),
                    passThresholdBps: 5100,
                    totalVotingPower: 100,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );

        // Mint governance NFTs
        partyAdmin.mintGovNft(party, address(john), 50);
        partyAdmin.mintGovNft(party, address(danny), 50);

        vm.warp(block.timestamp + 1);

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });
        john.makeProposal(party, p1, 0);

        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Voting, 50);

        vm.warp(block.timestamp + 98);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Voting, 50);

        // ensure defeated
        vm.warp(block.timestamp + 1);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Defeated, 50);

        // ensure can't execute proposal
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Defeated
            )
        );
        john.executeProposal(
            party,
            PartyParticipant.ExecutionOptions({
                proposalId: 1,
                proposal: p1,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds,
                progressData: abi.encodePacked([address(0)])
            })
        );
    }

    // The proposal passed, but it's now too late to execute because it went over the maxExecutableTime or whatever that variable is called
    function testGovernance_proposal_expiredAfterPassing() public {
        // Create party
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(john),
                    host2: address(danny),
                    passThresholdBps: 5100,
                    totalVotingPower: 100,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );

        // Mint governance NFTs
        partyAdmin.mintGovNft(party, address(john), 1);
        partyAdmin.mintGovNft(party, address(danny), 49);
        partyAdmin.mintGovNft(party, address(steve), 50);

        vm.warp(block.timestamp + 1);

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });
        john.makeProposal(party, p1, 0);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Voting, 1);

        steve.vote(party, 1, 0);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Passed, 51);

        vm.warp(block.timestamp + 98);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Passed, 51);

        vm.warp(block.timestamp + 300);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Ready, 51);

        // warp to maxExecutabletime
        vm.warp(9999999999);
        _assertProposalStatus(party, 1, PartyGovernance.ProposalStatus.Ready, 51);

        // warp past maxExecutabletime
        vm.warp(9999999999 + 1);

        // ensure can't execute proposal due to maxExecutableTime
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.ExecutionTimeExceededError.selector,
                9999999999,
                block.timestamp
            )
        );
        john.executeProposal(
            party,
            PartyParticipant.ExecutionOptions({
                proposalId: 1,
                proposal: p1,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds,
                progressData: abi.encodePacked([address(0)])
            })
        );
    }

    function testGovernance_emergencyWithdrawal() public {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(nicholas),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 300,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );
        vm.deal(address(party), 500 ether);
        uint256 initialBalance = globalDaoWalletAddress.balance;

        vm.prank(globalDaoWalletAddress);
        party.emergencyExecute(payable(globalDaoWalletAddress), "", 500 ether);

        assertEq(0, address(party).balance);
        uint256 balanceChange = globalDaoWalletAddress.balance - initialBalance;
        assertEq(balanceChange, 500 ether);
    }

    function testGovernance_emergencyExecute() public {
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(nicholas),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 300,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        // send toad
        vm.prank(address(1));
        toadz.safeTransferFrom(address(1), address(party), 1);

        // ensure has toad
        assertEq(toadz.ownerOf(1), address(party));

        // partydao admin try emergency withdrawal, ensure it works to transfer toad out
        vm.prank(globalDaoWalletAddress);
        party.emergencyExecute(
            address(toadz),
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)",
                address(party),
                address(globalDaoWalletAddress),
                1,
                ""
            ),
            0
        );
        assertEq(toadz.ownerOf(1), address(globalDaoWalletAddress));
    }

    function testMintPartCard_aboveTotalVotingPower() public {
        // Create party
        (Party party, , ) = partyAdmin.createParty(
            partyImpl,
            PartyAdmin.PartyCreationMinimalOptions({
                host1: address(this),
                host2: address(0),
                passThresholdBps: 5100,
                totalVotingPower: 55,
                preciousTokenAddress: address(toadz),
                preciousTokenId: 1,
                rageQuitTimestamp: 0,
                feeBps: 0,
                feeRecipient: payable(0)
            })
        );

        // Mint first governance NFT
        vm.expectEmit(true, true, true, true);
        emit PartyCardIntrinsicVotingPowerSet(1, 49);
        vm.expectEmit(true, true, true, true);
        emit PartyVotingSnapshotCreated(address(john), uint40(block.timestamp), 0, 49, false);
        partyAdmin.mintGovNft(party, address(john), 49, address(john));

        // Mint first governance NFT
        vm.expectEmit(true, true, true, true);
        emit PartyCardIntrinsicVotingPowerSet(2, 6);
        vm.expectEmit(true, true, true, true);
        emit PartyVotingSnapshotCreated(address(danny), uint40(block.timestamp), 0, 6, false);
        partyAdmin.mintGovNft(party, address(danny), 50, address(danny));
    }

    function testGovernance_cancel_badProposalHash() public {
        // Create party
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(this),
                    host2: address(0),
                    passThresholdBps: 5100,
                    totalVotingPower: 100,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );
        DummySimpleProposalEngineImpl engInstance = DummySimpleProposalEngineImpl(address(party));

        // Mint first governance NFT
        partyAdmin.mintGovNft(party, address(john), 49, address(john));

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalHashError.selector,
                party.getProposalHash(p1),
                bytes32(0)
            )
        );
        vm.prank(address(john));
        party.cancel(1, p1);
    }

    function testGovernance_cancel_badProposalState() public {
        // Create party
        (
            Party party,
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = partyAdmin.createParty(
                partyImpl,
                PartyAdmin.PartyCreationMinimalOptions({
                    host1: address(this),
                    host2: address(0),
                    passThresholdBps: 5100,
                    totalVotingPower: 49,
                    preciousTokenAddress: address(toadz),
                    preciousTokenId: 1,
                    rageQuitTimestamp: 0,
                    feeBps: 0,
                    feeRecipient: payable(0)
                })
            );
        DummySimpleProposalEngineImpl engInstance = DummySimpleProposalEngineImpl(address(party));

        // Mint first governance NFT
        partyAdmin.mintGovNft(party, address(john), 49, address(john));

        // Generate proposal
        PartyGovernance.Proposal memory p1 = PartyGovernance.Proposal({
            maxExecutableTime: 9999999999,
            proposalData: abi.encodePacked([0]),
            cancelDelay: uint40(1 days)
        });

        john.makeProposal(party, p1, 0);

        (PartyGovernance.ProposalStatus status, ) = party.getProposalStateInfo(1);
        vm.expectRevert(
            abi.encodeWithSelector(PartyGovernance.BadProposalStatusError.selector, status)
        );
        vm.prank(address(john));
        party.cancel(1, p1);
    }

    function _assertProposalStatus(
        Party party,
        uint256 proposalId,
        PartyGovernance.ProposalStatus expectedProposalStatus,
        uint96 expectedNumVotes
    ) private {
        (PartyGovernance.ProposalStatus ps, PartyGovernance.ProposalStateValues memory pv) = party
            .getProposalStateInfo(proposalId);
        assertEq(uint256(ps), uint256(expectedProposalStatus));
        assertEq(pv.votes, expectedNumVotes);
    }
}
