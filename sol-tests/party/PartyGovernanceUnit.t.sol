// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/party/PartyGovernance.sol";
import "../../contracts/globals/Globals.sol";
import "../TestUtils.sol";

contract DummyProposalExecutionEngine is IProposalExecutionEngine {
    event DummyProposalExecutionEngine_executeCalled(
        address context,
        ProposalExecutionStatus status,
        ExecuteProposalParams params
    );

    mapping (bytes32 => ProposalExecutionStatus) _statusByProposalId;
    mapping (bytes32 => uint256) _lastStepByProposalId;

    function initialize(address, bytes memory) external {}
    function executeProposal(ExecuteProposalParams memory params)
        external
        returns (ProposalExecutionStatus status)
    {
        uint256 numSteps = abi.decode(params.proposalData, (uint256));
        uint256 currStep = params.progressData.length > 0
            ? abi.decode(params.progressData, (uint256))
            : 0;
        require(
            currStep < numSteps &&
            _lastStepByProposalId[params.proposalId] == currStep,
            'INVALID_PROPOSAL_STEP'
        );
        _lastStepByProposalId[params.proposalId] = currStep + 1;
        _statusByProposalId[params.proposalId] =
            status = currStep + 1 < numSteps
            ? ProposalExecutionStatus.InProgress
            : ProposalExecutionStatus.Complete;
        emit DummyProposalExecutionEngine_executeCalled(
            address(this),
            status,
            params
        );
    }
    function getProposalExecutionStatus(bytes32 proposalId)
        external
        view
        returns (ProposalExecutionStatus)
    {
        return _statusByProposalId[proposalId];
    }
}

contract DummyTokenDistributor {
    event DummyTokenDistributor_createDistributionCalled(
        address caller,
        IERC20 token,
        uint256 amount
    );

    uint256 _lastId;

    function createDistribution(IERC20 token)
        external
        payable
        returns (TokenDistributor.DistributionInfo memory distInfo)
    {
        uint256 amount;
        if (address(token) == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            amount = address(this).balance;
            payable(0).transfer(amount);  // Burn it all to keep balances fresh.
        } else {
            amount = token.balanceOf(address(this));
            token.transfer(address(0), amount); // Burn it all to keep balances fresh.
        }
        distInfo.distributionId = ++_lastId;
        emit DummyTokenDistributor_createDistributionCalled(
            msg.sender,
            token,
            amount
        );
    }
}

contract TestablePartyGovernance is PartyGovernance {
    using LibSafeCast for uint256;

    constructor(
        IGlobals globals,
        GovernanceOpts memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        PartyGovernance(globals)
    {
        _initialize(opts, preciousTokens, preciousTokenIds);
    }

    function mockAdjustVotingPower(address owner, int192 votingPowerDelta, address delegate)
        external
    {
        _adjustVotingPower(owner, votingPowerDelta, delegate);
    }

    function transferVotingPower(address from, address to, uint256 power)
        external
    {
        _transferVotingPower(from, to, power);
    }

    function getProposalHash(Proposal memory proposal)
        external
        pure
        returns (bytes32 h)
    {
        return _getProposalHash(proposal);
    }

    function getDistributionShareOf(uint256 tokenId) external view returns (uint256 s) {}

    function ownerOf(uint256 tokenId) external view returns (address o) {}

    function getVotes(uint256 proposalId) external view returns (uint96) {
        (, ProposalInfoValues memory v) = this.getProposalStates(proposalId);
        return v.votes;
    }

    function getVotingPowerSnapshotAt(address voter, uint256 timestamp)
        external
        view
        returns (VotingPowerSnapshot memory snap)
    {
        return _getVotingPowerSnapshotAt(voter, uint40(timestamp));
    }
}

contract PartyGovernanceUnitTest is Test, TestUtils {
    event Proposed(
        uint256 proposalId,
        address proposer,
        PartyGovernance.Proposal proposal
    );
    event ProposalAccepted(
        uint256 proposalId,
        address voter,
        uint256 weight
    );
    event ProposalPassed(uint256 proposalId);
    event ProposalVetoed(uint256 proposalId, address host);
    event ProposalExecuted(uint256 proposalId, address executor);
    event ProposalCompleted(uint256 proposalId);
    event DistributionCreated(uint256 distributionId, IERC20 token);
    event VotingPowerDelegated(address owner, address delegate);
    event PreciousListSet(IERC721[] tokens, uint256[] tokenIds);
    event DummyProposalExecutionEngine_executeCalled(
        address context,
        IProposalExecutionEngine.ProposalExecutionStatus status,
        IProposalExecutionEngine.ExecuteProposalParams params
    );

    PartyGovernance.GovernanceOpts defaultGovernanceOpts;
    Globals globals = new Globals(address(this));
    DummyProposalExecutionEngine proposalEngine = new DummyProposalExecutionEngine();
    DummyTokenDistributor tokenDistributor = new DummyTokenDistributor();

    constructor() {
        globals.setAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL, address(proposalEngine));
        globals.setAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR, address(tokenDistributor));
        defaultGovernanceOpts.hosts.push(_randomAddress());
        defaultGovernanceOpts.hosts.push(_randomAddress());
        defaultGovernanceOpts.voteDuration = 1 days;
        defaultGovernanceOpts.executionDelay = 12 hours;
        defaultGovernanceOpts.passThresholdBps = 0.51e4;
        defaultGovernanceOpts.totalVotingPower = 100e18;
    }

    function _createPreciousTokens(uint256 count)
        private
        view
        returns (IERC721[] memory tokens, uint256[] memory tokenIds)
    {
        tokens = new IERC721[](count);
        tokenIds = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            // Doesn't actually have to be real tokens for these tests.
            tokens[i] = IERC721(_randomAddress());
            tokenIds[i] = _randomUint256();
        }
    }

    function _createGovernance(
        uint96 totalVotingPower,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        private
        returns (TestablePartyGovernance gov)
    {
        defaultGovernanceOpts.totalVotingPower = totalVotingPower;
        return new TestablePartyGovernance(
            globals,
            defaultGovernanceOpts,
            preciousTokens,
            preciousTokenIds
        );
    }

    function _createProposal(uint256 numSteps)
        private
        view
        returns (PartyGovernance.Proposal memory prop)
    {
        return PartyGovernance.Proposal({
            // Expires right after execution delay.
            maxExecutableTime: uint40(block.timestamp) + defaultGovernanceOpts.executionDelay,
            nonce: _randomUint256(),
            proposalData: abi.encode(numSteps)
        });
    }

    function _getRandomDefaultHost() private view returns (address) {
        return defaultGovernanceOpts.hosts[
            _randomUint256() % defaultGovernanceOpts.hosts.length
        ];
    }

    // One undelegated voter with 51/100 intrinsic VP.
    // One step proposal.
    function testProposalLifecycle_oneVoter() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        (PartyGovernance.ProposalState propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Invalid);

        // Undelegated voter submits proposal.
        vm.expectEmit(false, false, false, true);
        emit Proposed(proposalId, undelegatedVoter, proposal);
        // Votes are automatically cast by proposer.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(proposalId, undelegatedVoter, 51e18);
        // Voter has majority VP so it also passes immediately.
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        (propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Passed);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);
        (propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Ready);

        // Execute the proposal as the single voter.
        vm.expectEmit(false, false, false, true);
        emit DummyProposalExecutionEngine_executeCalled(
            address(gov),
            IProposalExecutionEngine.ProposalExecutionStatus.Complete,
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: bytes32(proposalId),
                proposalData: proposal.proposalData,
                progressData: "",
                flags: 0,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds
            })
        );
        vm.expectEmit(false, false, false, true);
        emit ProposalExecuted(proposalId, undelegatedVoter);
        vm.expectEmit(false, false, false, true);
        emit ProposalCompleted(proposalId);
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );

        (propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Complete);
    }

    // One undelegated voter with 51/100 intrinsic VP.
    // Two step proposal.
    function testProposalLifecycle_oneVoter_twoStep() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a two-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(2);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal.
        vm.expectEmit(false, false, false, true);
        emit Proposed(proposalId, undelegatedVoter, proposal);
        // Votes are automatically cast by proposer.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(proposalId, undelegatedVoter, 51e18);
        // Voter has majority VP so it also passes immediately.
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);
        // Execute the proposal as the single voter. (1/2)
        vm.expectEmit(false, false, false, true);
        emit DummyProposalExecutionEngine_executeCalled(
            address(gov),
            IProposalExecutionEngine.ProposalExecutionStatus.InProgress,
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: bytes32(proposalId),
                proposalData: proposal.proposalData,
                progressData: "",
                flags: 0,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds
            })
        );
        vm.expectEmit(false, false, false, true);
        emit ProposalExecuted(proposalId, undelegatedVoter);
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );

        (PartyGovernance.ProposalState propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.InProgress);

        // Execute the proposal as the single voter. (2/2)
        vm.expectEmit(false, false, false, true);
        emit DummyProposalExecutionEngine_executeCalled(
            address(gov),
            IProposalExecutionEngine.ProposalExecutionStatus.Complete,
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: bytes32(proposalId),
                proposalData: proposal.proposalData,
                progressData: abi.encode(1),
                flags: 0,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds
            })
        );
        vm.expectEmit(false, false, false, true);
        emit ProposalExecuted(proposalId, undelegatedVoter);
        vm.expectEmit(false, false, false, true);
        emit ProposalCompleted(proposalId);
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            abi.encode(1)
        );

        (propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Complete);
    }

    // One undelegated voter with 100/100 intrinsic VP.
    // One step proposal.
    function testProposalLifecycle_oneVoterUnanimous() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 100/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 100e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal.
        vm.expectEmit(false, false, false, true);
        emit Proposed(proposalId, undelegatedVoter, proposal);
        // Votes are automatically cast by proposer.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(proposalId, undelegatedVoter, 100e18);
        // Voter has majority VP so it also passes immediately.
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);
        // Execute the proposal as the single voter.
        vm.expectEmit(false, false, false, true);
        emit DummyProposalExecutionEngine_executeCalled(
            address(gov),
            IProposalExecutionEngine.ProposalExecutionStatus.Complete,
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: bytes32(proposalId),
                proposalData: proposal.proposalData,
                progressData: "",
                // Should be flagged unanimous.
                flags: LibProposal.PROPOSAL_FLAG_UNANIMOUS,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds
            })
        );
        vm.expectEmit(false, false, false, true);
        emit ProposalExecuted(proposalId, undelegatedVoter);
        vm.expectEmit(false, false, false, true);
        emit ProposalCompleted(proposalId);
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );
    }

    // One undelegated voter with 75/100 intrinsic VP.
    // One undelegated voter with 25/100 intrinsic VP.
    // One step proposal.
    function testProposalLifecycle_twoVotersUnanimous() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter1 = _randomAddress();
        address undelegatedVoter2 = _randomAddress();
        // undelegatedVoter1 has 75/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter1, 75e18, address(0));
        // undelegatedVoter2 has 25/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter2, 25e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter 1 submits proposal.
        vm.expectEmit(false, false, false, true);
        emit Proposed(proposalId, undelegatedVoter1, proposal);
        // Votes are automatically cast by proposer.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(proposalId, undelegatedVoter1, 75e18);
        // Voter has majority VP so it also passes immediately.
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(undelegatedVoter1);
        assertEq(gov.propose(proposal), proposalId);

        // Undelegated voter 2 votes.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(proposalId, undelegatedVoter2, 25e18);
        vm.prank(undelegatedVoter2);
        gov.accept(proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);
        // Execute the proposal as the single voter.
        vm.expectEmit(false, false, false, true);
        emit DummyProposalExecutionEngine_executeCalled(
            address(gov),
            IProposalExecutionEngine.ProposalExecutionStatus.Complete,
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: bytes32(proposalId),
                proposalData: proposal.proposalData,
                progressData: "",
                // Should be flagged unanimous.
                flags: LibProposal.PROPOSAL_FLAG_UNANIMOUS,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds
            })
        );
        vm.expectEmit(false, false, false, true);
        emit ProposalExecuted(proposalId, undelegatedVoter1);
        vm.expectEmit(false, false, false, true);
        emit ProposalCompleted(proposalId);
        vm.prank(undelegatedVoter1);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );
    }

    // Try to execute a proposal that hasn't passed.
    function testProposalLifecycle_cannotExecuteWithoutPassing() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 50e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal.
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Try to execute proposal (fail).
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.BadProposalStateError.selector,
            PartyGovernance.ProposalState.Voting
        ));
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);
        // Try again (fail).
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.BadProposalStateError.selector,
            PartyGovernance.ProposalState.Voting
        ));
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );
    }

    // Try to execute a proposal before the execution delay has passed.
    function testProposalLifecycle_cannotExecuteBeforeExecutionDelay() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Try to execute proposal (fail).
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.BadProposalStateError.selector,
            PartyGovernance.ProposalState.Passed
        ));
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );
    }

    // Try to execute a proposal after its maxExecutableTime.
    function testProposalLifecycle_cannotExecuteAfterExpiration() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Skip past the proposal expiration.
        vm.warp(proposal.maxExecutableTime + 1);

        // Try to execute proposal (fail).
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.ExecutionTimeExceededError.selector,
            proposal.maxExecutableTime,
            uint40(block.timestamp)
        ));
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );
    }

    // Try to execute a proposal that has already completed.
    function testProposalLifecycle_cannotExecuteCompletedProposal() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        // Execute (1/1).
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );

        (PartyGovernance.ProposalState propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Complete);

        // Try to execute again.
        bytes32 expectedHash = gov.getProposalHash(proposal);
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.BadProposalStateError.selector,
            PartyGovernance.ProposalState.Complete
        ));
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );
    }

    // Try to execute a proposal that has been modified.
    function testProposalLifecycle_cannotExecuteIfModified() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        // Try to execute proposal (fail).
        bytes32 expectedHash = gov.getProposalHash(proposal);
        proposal.proposalData = bytes('naughty');
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.BadProposalHashError.selector,
            gov.getProposalHash(proposal),
            expectedHash
        ));
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );
    }

    // only host can veto
    function testProposalLifecycle_onlyHostCanVeto() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 50e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal and votes, but does not have enough
        // to pass on their own.
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Non-host tries to veto.
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.OnlyPartyHostError.selector
        ));
        vm.prank(undelegatedVoter);
        gov.veto(proposalId);
    }

    // cannot veto invalid proposal
    function testProposalLifecycle_cannotVetoInvalidProposal() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 50e18, address(0));

        uint256 proposalId = gov.lastProposalId() + 1;
        address host = _getRandomDefaultHost();
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.BadProposalStateError.selector,
            PartyGovernance.ProposalState.Invalid
        ));
        vm.prank(host);
        gov.veto(proposalId);
    }

    // can veto a proposal that's in vote.
    function testProposalLifecycle_canVetoVotingProposal() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 50e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal and votes, but does not have enough
        // to pass on their own.
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        (PartyGovernance.ProposalState propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Voting);

        // Host vetos.
        address host = _getRandomDefaultHost();
        vm.prank(host);
        gov.veto(proposalId);

        (propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Defeated);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        // Fails to execute.
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.BadProposalStateError.selector,
            PartyGovernance.ProposalState.Defeated
        ));
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );
    }

    // can veto a proposal that's ready.
    function testProposalLifecycle_canVetoReadyProposal() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        (PartyGovernance.ProposalState propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Ready);

        // Host vetos.
        address host = _getRandomDefaultHost();
        vm.prank(host);
        gov.veto(proposalId);

        (propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Defeated);

        // Fails to execute.
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.BadProposalStateError.selector,
            PartyGovernance.ProposalState.Defeated
        ));
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );
    }

    // try to veto a proposal that's in progress.
    function testProposalLifecycle_cannotVetoInProgressProposal() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a two-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(2);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        // Execute (1/2)
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );

        // Host tries to veto.
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.BadProposalStateError.selector,
            PartyGovernance.ProposalState.InProgress
        ));
        vm.prank(_getRandomDefaultHost());
        gov.veto(proposalId);
    }

    // try to veto a proposal that's completed.
    function testProposalLifecycle_cannotVetoCompleteProposal() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        // Execute (1/1)
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );

        // Host tries to veto.
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.BadProposalStateError.selector,
            PartyGovernance.ProposalState.Complete
        ));
        vm.prank(_getRandomDefaultHost());
        gov.veto(proposalId);
    }

    // An InProgress proposal that has expired is still executable.
    function testProposalLifecycle_canStillExecuteExpiredInProgressProposal() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a two-step proposal.
        // By default the proposal expires 1 second after the executable delay.
        PartyGovernance.Proposal memory proposal = _createProposal(2);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        // Execute (1/2)
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );

        // Skip past the proposal's maxExecutableTime.
        vm.warp(proposal.maxExecutableTime + 1);
        (PartyGovernance.ProposalState propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.InProgress);

        // Execute (2/2)
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            abi.encode(1)
        );
        (propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Complete);
    }

    // Try to execute a proposal after the voting window has expired and it has not passed.
    function testProposalLifecycle_cannotExecuteIfVotingWindowExpired() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        defaultGovernanceOpts.executionDelay = 60;
        defaultGovernanceOpts.voteDuration = 61;
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 50e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal.
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        (PartyGovernance.ProposalState propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Voting);

        // Skip past voting window.
        skip(defaultGovernanceOpts.voteDuration);

        // Try to execute proposal (fail).
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.BadProposalStateError.selector,
            PartyGovernance.ProposalState.Defeated
        ));
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            ""
        );
    }

    // One undelegated voter with 25/100 intrinsic VP.
    // One delegated voter with 25/100 intrinsic VP
    // One delegate with 25/100 intrinsic + 25 delegated VP.
    function testVoting_passing_mixedVotes() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate = _randomAddress();
        address delegatedVoter = _randomAddress();
        address undelegatedVoter = _randomAddress();
        // delegate has 25 intrinsic VP (delegated to no one/self), 25 delegated VP.
        gov.mockAdjustVotingPower(delegate, 25e18, address(0)); // self-delegated
        // delegatedVoter has 25 intrinsic VP (delegated to delegate)
        gov.mockAdjustVotingPower(delegatedVoter, 25e18, delegate);
        // undelegatedVoter has 25 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 25e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Delegated voter submits proposal.
        // No intrinsic or delegated votes so no vote cast during proposal.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(proposalId, delegatedVoter, 0);
        vm.prank(delegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        (PartyGovernance.ProposalState propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Voting);

        // Undelegated (self-delegated) voter votes.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(proposalId, undelegatedVoter, 25e18);
        vm.prank(undelegatedVoter);
        gov.accept(proposalId);

        // Delegate votes with delegated and intrinsic voting power.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(proposalId, delegate, 50e18);
        // Combined, votes are enough (75%) to push it over the pass threshold (50%).
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(delegate);
        gov.accept(proposalId);

        (propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Passed);
    }

    // One undelegated voter with 10/100 intrinsic VP.
    // One delegated voter with 10/100 intrinsic VP
    // One delegate with 30/100 intrinsic + 10 delegated VP.
    // Combined 10 + 10 + 30 -> 50 < 51 (no pass)
    function testVoting_notPassing_mixedVotes() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate = _randomAddress();
        address delegatedVoter = _randomAddress();
        address undelegatedVoter = _randomAddress();
        // delegate has 30 intrinsic VP (delegated to no one/self), 10 delegated VP.
        gov.mockAdjustVotingPower(delegate, 30e18, address(0)); // self-delegated
        // delegatedVoter has 10 intrinsic VP (delegated to delegate)
        gov.mockAdjustVotingPower(delegatedVoter, 10e18, delegate);
        // undelegatedVoter has 10 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 10e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Delegated voter submits proposal.
        // No intrinsic or delegated votes so no vote cast during proposal.
        emit ProposalAccepted(proposalId, delegatedVoter, 0);
        vm.prank(delegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Undelegated (self-delegated) voter votes.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(proposalId, undelegatedVoter, 10e18);
        vm.prank(undelegatedVoter);
        gov.accept(proposalId);

        // Delegate votes with delegated and intrinsic voting power.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(proposalId, delegate, 40e18);
        vm.prank(delegate);
        gov.accept(proposalId);

        // 10 + 10 + 30 = 50, but need 51/100 to pass.
        (PartyGovernance.ProposalState propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Voting);
    }

    // Try to vote outside the voting window.
    function testVoting_cannotVoteOutsideVotingWindow() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter1 = _randomAddress();
        address undelegatedVoter2 = _randomAddress();
        // undelegatedVoter1 has 50/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter1, 50e18, address(0));
        // undelegatedVoter2 has 1/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter2, 1e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter 1 submits proposal (and votes).
        vm.prank(undelegatedVoter1);
        assertEq(gov.propose(proposal), proposalId);

        (PartyGovernance.ProposalState propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Voting);

        // Skip past voting window.
        skip(defaultGovernanceOpts.voteDuration);

        (propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Defeated);

        // Undelegated voter 2 tries to vote.
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.BadProposalStateError.selector,
            PartyGovernance.ProposalState.Defeated
        ));
        vm.prank(undelegatedVoter2);
        gov.accept(proposalId);
    }

    // Try to vote twice (undelegated voter)
    function testVoting_cannotVoteTwice() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter, 50e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter submits proposal (and votes).
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Try to vote again.
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.AlreadyVotedError.selector,
            undelegatedVoter
        ));
        vm.prank(undelegatedVoter);
        gov.accept(proposalId);
    }

    // Try to vote twice (delegate)
    function testVoting_delegateCannotVoteTwice() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate = _randomAddress();
        address delegatedVoter = _randomAddress();
        // delegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(delegatedVoter, 50e18, delegate);

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Delegate submits proposal (and votes).
        vm.prank(delegate);
        assertEq(gov.propose(proposal), proposalId);

        // Try to vote again.
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.AlreadyVotedError.selector,
            delegate
        ));
        vm.prank(delegate);
        gov.accept(proposalId);
    }

    // Try to vote twice (delegated voter)
    function testVoting_delegatedVoterCannotVoteTwice() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate = _randomAddress();
        address delegatedVoter = _randomAddress();
        // delegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(delegatedVoter, 50e18, delegate);

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Delegated voter submits proposal (and votes).
        vm.prank(delegatedVoter);
        assertEq(gov.propose(proposal), proposalId);

        // Try to vote again.
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.AlreadyVotedError.selector,
            delegatedVoter
        ));
        vm.prank(delegatedVoter);
        gov.accept(proposalId);
    }

    // Try to vote on a vetoed proposal.
    function testVoting_cannotVoteAfterVeto() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter1 = _randomAddress();
        address undelegatedVoter2 = _randomAddress();
        // undelegatedVoter1 has 50/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter1, 50e18, address(0));
        // undelegatedVoter2 has 1/100 intrinsic VP (delegated to no one/self)
        gov.mockAdjustVotingPower(undelegatedVoter2, 50e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Undelegated voter 1 submits proposal (and votes).
        vm.prank(undelegatedVoter1);
        assertEq(gov.propose(proposal), proposalId);

        (PartyGovernance.ProposalState propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Voting);

        // Host vetos.
        address host = _getRandomDefaultHost();
        vm.expectEmit(false, false, false, true);
        emit ProposalVetoed(proposalId, host);
        vm.prank(host);
        gov.veto(proposalId);

        (propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Defeated);

        // Undelegated voter 2 tries to vote.
        vm.expectRevert(abi.encodeWithSelector(
            PartyGovernance.BadProposalStateError.selector,
            PartyGovernance.ProposalState.Defeated
        ));
        vm.prank(undelegatedVoter2);
        gov.accept(proposalId);
    }

    // Vote using VP from proposal time.
    function testVoting_votingUsesProposalTimeVotingPower() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate = _randomAddress();
        address undelegatedVoter = _randomAddress();
        address delegatedVoter = _randomAddress();
        address proposer = _randomAddress();
        // proposer has 1 wei of intrinsic VP (just enough to propose), delegated to
        // an address we won't use.
        gov.mockAdjustVotingPower(proposer, 1, address(0xbadb01));
        // delegate has 30 intrinsic, 50 delegated VP
        gov.mockAdjustVotingPower(delegate, 30e18, address(0));
        // delegatedVoter has 20 intrinsic delegated to delegate.
        gov.mockAdjustVotingPower(delegatedVoter, 20e18, delegate);
        // undelegatedVoter has 1 intrinsing VP, delegated to no one/self.
        gov.mockAdjustVotingPower(undelegatedVoter, 1e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // Propose it from proposer, locking in the proposal time
        // and not casting any votes because proposer has delegated to
        // someone else.
        vm.prank(proposer);
        assertEq(gov.propose(proposal), proposalId);

        // Advance time, moving VP around each time.
        skip(1);
        // Delegate transfers all voting power to undelegatedVoter.
        gov.transferVotingPower(delegate, undelegatedVoter, 30e18);
        skip(1);
        // delegatedVoter transfers all voting power to undelegatedVoter.
        gov.transferVotingPower(delegatedVoter, undelegatedVoter, 20e18);
        skip(1);
        // Now undelegatedVoter has enough VP (51) to pass on their own and
        // will accept the proposal, but accept will use their VP at proposal
        // time so it will only count as 1 VP.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(
            proposalId,
            undelegatedVoter,
            1e18 // Proposal time VP.
        );
        vm.prank(undelegatedVoter);
        gov.accept(proposalId);

        // delegatedVoter will vote, who does not have any VP now and also had
        // no VP at proposal time.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(
            proposalId,
            delegatedVoter,
            0 // Proposal time VP.
        );
        vm.prank(delegatedVoter);
        gov.accept(proposalId);

        (PartyGovernance.ProposalState propState,) = gov.getProposalStates(proposalId);
        assertTrue(propState == PartyGovernance.ProposalState.Voting);

        // Delegate will vote, who does not have any VP now but at proposal time
        // had a total of 50, which will make the proposal pass.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(
            proposalId,
            delegate,
            50e18 // Proposal time VP.
        );
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(delegate);
        gov.accept(proposalId);
    }

    // Circular delegation.
    function testVoting_circularDelegation() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate1 = _randomAddress();
        address delegate2 = _randomAddress();
        // Set up circular delegation just to be extra tricky.
        // delegate has 1 intrinsic, 51 delegated VP
        gov.mockAdjustVotingPower(delegate1, 1e18, delegate2);
        // delegate2 has 50 intrinsic, 1 delegated VP
        gov.mockAdjustVotingPower(delegate2, 50e18, delegate1);

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.lastProposalId() + 1;

        // delegate2 proposes and votes with their 1 effective VP.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(
            proposalId,
            delegate2,
            1e18
        );
        vm.prank(delegate2);
        gov.propose(proposal);

        assertEq(uint256(gov.getVotes(proposalId)), 1e18);

        // delegate1 votes with their 50 effective VP.
        vm.expectEmit(false, false, false, true);
        emit ProposalAccepted(
            proposalId,
            delegate1,
            50e18
        );
        // With 51 total, the proposal will pass.
        vm.expectEmit(false, false, false, true);
        emit ProposalPassed(proposalId);
        vm.prank(delegate1);
        gov.accept(proposalId);

        assertEq(uint256(gov.getVotes(proposalId)), 51e18);
    }

    // Cannot adjust voting power below 0.
    function testVotingPower_cannotAdjustVotingPowerBelowZero() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51 intrinsic VP
        gov.mockAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Try to adjust below 0.
        vm.expectRevert(abi.encodeWithSelector(
            LibSafeCast.Int192ToUint96CastOutOfRange.selector,
            int192(-1)
        ));
        gov.mockAdjustVotingPower(undelegatedVoter, -51e18 - 1, address(0));
    }

    // _adjustVotingPower() updates delegated VP correctly
    function testVotingPower_adjustVotingPowerUpdatesDelegatesCorrectly() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate1 = _randomAddress();
        address delegate2 = _randomAddress();
        address voter = _randomAddress();
        // voter has 50 intrinsic VP, delegated to delegate1.
        gov.mockAdjustVotingPower(voter, 50e18, delegate1);
        // delegate1 has 10 intrinsic VP, delegated to delegate2.
        gov.mockAdjustVotingPower(delegate1, 10e18, delegate2);
        // delegate2 has 20 intrinsic VP, delegated to self.
        gov.mockAdjustVotingPower(delegate2, 20e18, address(0));

        // Remove 5 intrinsic VP from voter and redelegate to delegate2.
        gov.mockAdjustVotingPower(voter, -5e18, delegate2);
        // Add 5 intrinsic VP to delegate1 and keep delegation to delegate2.
        gov.mockAdjustVotingPower(delegate1, 5e18, delegate2);
        // Remove 3 intrinsic VP from delegate1 and keep delegation to delegate2.
        gov.mockAdjustVotingPower(delegate1, -3e18, delegate2);
        // Redelegate delegate2 to delegate1.
        gov.mockAdjustVotingPower(delegate2, 0, delegate1);

        // Now check total VPs.
        // voter: 50 - 5 = 45 intrinsic (delegated: delegate2) + 0 delegated -> 0
        assertEq(
            uint256(gov.getVotingPowerAt(voter, uint40(block.timestamp))),
            0e18
        );
        // delegate1: 10 + 5 - 3 = 12 intrinsic (delegated: delegate2) + 20 delegated -> 20
        assertEq(
            uint256(gov.getVotingPowerAt(delegate1, uint40(block.timestamp))),
            20e18
        );
        // delegate2: 20 intrinsic (delegated: deleate1) + 45 + 12 = 57 delegated -> 57
        assertEq(
            uint256(gov.getVotingPowerAt(delegate2, uint40(block.timestamp))),
            57e18
        );

        // Check internal accounting for voter.
        {
            PartyGovernance.VotingPowerSnapshot memory snap =
                gov.getVotingPowerSnapshotAt(voter, block.timestamp);
            assertEq(uint256(snap.intrinsicVotingPower), 45e18);
            assertEq(uint256(snap.delegatedVotingPower), 0);
        }
        // Check internal accounting for delegate1.
        {
            PartyGovernance.VotingPowerSnapshot memory snap =
                gov.getVotingPowerSnapshotAt(delegate1, block.timestamp);
            assertEq(uint256(snap.intrinsicVotingPower), 12e18);
            assertEq(uint256(snap.delegatedVotingPower), 20e18);
        }
        // Check internal accounting for delegate2.
        {
            PartyGovernance.VotingPowerSnapshot memory snap =
                gov.getVotingPowerSnapshotAt(delegate2, block.timestamp);
            assertEq(uint256(snap.intrinsicVotingPower), 20e18);
            assertEq(uint256(snap.delegatedVotingPower), 57e18);
        }
    }

    // delegate(self) == delegate(0) if no prior delegate
    function testVotingPower_delegateSelfIsSameAsDelegateZero() external {
        TestablePartyGovernance gov;
        (IERC721[] memory preciousTokens, uint256[] memory preciousTokenIds) =
            _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address voter1 = _randomAddress();
        address voter2 = _randomAddress();
        // voter has 50 intrinsic VP, delegated to zero.
        gov.mockAdjustVotingPower(voter1, 50e18, address(0));
        // voter has 25 intrinsic VP, delegated to self.
        gov.mockAdjustVotingPower(voter2, 25e18, voter2);

        assertEq(gov.getVotingPowerAt(voter1, uint40(block.timestamp)), 50e18);
        assertEq(gov.getVotingPowerAt(voter2, uint40(block.timestamp)), 25e18);

        // Now flip it via delegateVotingPower()
        vm.prank(voter1);
        gov.delegateVotingPower(voter1);
        vm.prank(voter2);
        gov.delegateVotingPower(address(0));

        assertEq(gov.getVotingPowerAt(voter1, uint40(block.timestamp)), 50e18);
        assertEq(gov.getVotingPowerAt(voter2, uint40(block.timestamp)), 25e18);
    }
}
