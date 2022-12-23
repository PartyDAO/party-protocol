// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/party/PartyGovernance.sol";
import "../../contracts/distribution/ITokenDistributor.sol";
import "../../contracts/globals/Globals.sol";
import "../DummyERC20.sol";
import "../DummyERC1155.sol";
import "../DummyERC721.sol";
import "../TestUtils.sol";

contract DummyProposalExecutionEngine is IProposalExecutionEngine {
    event DummyProposalExecutionEngine_executeCalled(
        address context,
        bool completed,
        ExecuteProposalParams params
    );
    event DummyProposalExecutionEngine_cancelCalled(address context, uint256 proposalId);

    mapping(uint256 => uint256) _lastStepByProposalId;

    function initialize(address, bytes memory) external {}

    function executeProposal(
        ExecuteProposalParams memory params
    ) external returns (bytes memory nextProgressData) {
        uint256 numSteps = abi.decode(params.proposalData, (uint256));
        uint256 currStep = params.progressData.length > 0
            ? abi.decode(params.progressData, (uint256))
            : 0;
        require(
            currStep < numSteps && _lastStepByProposalId[params.proposalId] == currStep,
            "INVALID_PROPOSAL_STEP"
        );
        _lastStepByProposalId[params.proposalId] = currStep + 1;
        bool completed = currStep + 1 >= numSteps;
        nextProgressData = completed ? bytes("") : abi.encode(currStep + 1);
        emit DummyProposalExecutionEngine_executeCalled(address(this), completed, params);
    }

    function cancelProposal(uint256 proposalId) external {
        emit DummyProposalExecutionEngine_cancelCalled(address(this), proposalId);
    }
}

contract DummyTokenDistributor is ITokenDistributor {
    event DummyTokenDistributor_createDistributionCalled(
        ITokenDistributorParty party,
        ITokenDistributor.TokenType tokenType,
        address token,
        uint256 tokenId,
        address payable feeRecipient,
        uint16 feeBps,
        uint256 amount,
        uint256 id
    );

    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address payable public SINK = payable(address(12345678));
    uint256 public lastId;

    function createNativeDistribution(
        ITokenDistributorParty party,
        address payable feeRecipient,
        uint16 feeBps
    ) external payable returns (DistributionInfo memory distInfo) {
        uint256 amount = address(this).balance;
        SINK.transfer(amount); // Burn it all to keep balances fresh.
        distInfo.distributionId = ++lastId;
        emit DummyTokenDistributor_createDistributionCalled(
            party,
            ITokenDistributor.TokenType.Native,
            ETH_ADDRESS,
            0,
            feeRecipient,
            feeBps,
            amount,
            distInfo.distributionId
        );
    }

    function createErc20Distribution(
        IERC20 token,
        ITokenDistributorParty party,
        address payable feeRecipient,
        uint16 feeBps
    ) external returns (DistributionInfo memory distInfo) {
        uint256 amount = token.balanceOf(address(this));
        token.transfer(SINK, amount); // Burn it all to keep balances fresh.
        distInfo.distributionId = ++lastId;
        emit DummyTokenDistributor_createDistributionCalled(
            party,
            ITokenDistributor.TokenType.Erc20,
            address(token),
            0,
            feeRecipient,
            feeBps,
            amount,
            distInfo.distributionId
        );
    }

    function claim(DistributionInfo calldata, uint256) external returns (uint128 amountClaimed) {}

    function claimFee(DistributionInfo calldata, address payable) external {}

    function batchClaim(
        DistributionInfo[] calldata infos,
        uint256[] calldata partyTokenIds
    ) external returns (uint128[] memory amountsClaimed) {}

    /// @inheritdoc ITokenDistributor
    function batchClaimFee(
        DistributionInfo[] calldata infos,
        address payable[] calldata recipients
    ) external {}

    function getClaimAmount(
        ITokenDistributorParty party,
        uint256 memberSupply,
        uint256 partyTokenId
    ) public view returns (uint128) {}

    function wasFeeClaimed(ITokenDistributorParty, uint256) external view returns (bool) {}

    function hasPartyTokenIdClaimed(
        ITokenDistributorParty,
        uint256,
        uint256
    ) external view returns (bool) {}

    function getRemainingMemberSupply(
        ITokenDistributorParty,
        uint256
    ) external view returns (uint128) {}
}

contract TestablePartyGovernance is PartyGovernance {
    using LibSafeCast for uint256;

    modifier onlyDelegateCall() override {
        _;
    }

    constructor(
        IGlobals globals,
        GovernanceOpts memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) PartyGovernance(globals) {
        _initialize(opts, preciousTokens, preciousTokenIds);
    }

    function rawAdjustVotingPower(
        address owner,
        int192 votingPowerDelta,
        address delegate
    ) external {
        _adjustVotingPower(owner, votingPowerDelta, delegate);
    }

    function transferVotingPower(address from, address to, uint256 power) external {
        _transferVotingPower(from, to, power);
    }

    function getDistributionShareOf(uint256 tokenId) external view returns (uint256 s) {}

    function ownerOf(uint256 tokenId) external view returns (address o) {}

    function getVotes(uint256 proposalId) external view returns (uint96) {
        (, ProposalStateValues memory v) = this.getProposalStateInfo(proposalId);
        return v.votes;
    }

    function getVotingPowerSnapshotAt(
        address voter,
        uint256 timestamp,
        uint256 hintIndex
    ) external view returns (VotingPowerSnapshot memory snap) {
        return _getVotingPowerSnapshotAt(voter, uint40(timestamp), hintIndex);
    }

    function getProposalStatus(
        uint256 proposalId
    ) external view returns (PartyGovernance.ProposalStatus status) {
        (status, ) = this.getProposalStateInfo(proposalId);
    }

    function getNextProposalId() external view returns (uint256) {
        return lastProposalId + 1;
    }

    function testGetProposalHash(Proposal memory proposal) public pure returns (bytes32 h) {
        // Hash twice in a row to ensure temporarily overwritten fields are
        // actually temporary. Don't compile with optimizer plz.
        h = getProposalHash(proposal);
        h = getProposalHash(proposal);
    }

    function hashPreciousList(
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) public pure returns (bytes32 h) {
        h = _hashPreciousList(preciousTokens, preciousTokenIds);
    }
}

contract PartyGovernanceUnitTest is Test, TestUtils {
    event Proposed(uint256 proposalId, address proposer, PartyGovernance.Proposal proposal);
    event ProposalAccepted(uint256 proposalId, address voter, uint256 weight);
    event ProposalPassed(uint256 indexed proposalId);
    event ProposalVetoed(uint256 indexed proposalId, address host);
    event ProposalCancelled(uint256 indexed proposalId);
    event ProposalExecuted(uint256 indexed proposalId, address executor, bytes nextProgressData);
    event DistributionCreated(uint256 distributionId, IERC20 token);
    event VotingPowerDelegated(address indexed owner, address delegate);
    event HostStatusTransferred(address oldHost, address newHost);
    event DummyProposalExecutionEngine_executeCalled(
        address context,
        bool completed,
        IProposalExecutionEngine.ExecuteProposalParams params
    );
    event DummyProposalExecutionEngine_cancelCalled(address context, uint256 proposalId);
    event DummyTokenDistributor_createDistributionCalled(
        ITokenDistributorParty party,
        ITokenDistributor.TokenType tokenType,
        address token,
        uint256 tokenId,
        address payable feeRecipient,
        uint16 feeBps,
        uint256 amount,
        uint256 id
    );

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    PartyGovernance.GovernanceOpts defaultGovernanceOpts;
    Globals globals = new Globals(address(this));
    DummyProposalExecutionEngine proposalEngine = new DummyProposalExecutionEngine();
    DummyTokenDistributor tokenDistributor = new DummyTokenDistributor();

    constructor() {
        globals.setAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL, address(proposalEngine));
        globals.setAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR, address(tokenDistributor));
        globals.setUint256(LibGlobals.GLOBAL_PROPOSAL_MAX_CANCEL_DURATION, 30 days);
        defaultGovernanceOpts.hosts.push(_randomAddress());
        defaultGovernanceOpts.hosts.push(_randomAddress());
        defaultGovernanceOpts.voteDuration = 1 days;
        defaultGovernanceOpts.executionDelay = 12 hours;
        defaultGovernanceOpts.passThresholdBps = 0.51e4;
        defaultGovernanceOpts.totalVotingPower = 100e18;
        defaultGovernanceOpts.feeBps = 0.025e4;
        defaultGovernanceOpts.feeRecipient = _randomAddress();
    }

    function _createPreciousTokens(
        uint256 count
    ) private view returns (IERC721[] memory tokens, uint256[] memory tokenIds) {
        tokens = new IERC721[](count);
        tokenIds = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            // Doesn't actually have to be real tokens for these tests.
            tokens[i] = IERC721(_randomAddress());
            tokenIds[i] = _randomUint256();
        }
    }

    function _createGovernance(
        uint96 totalVotingPower,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) private returns (TestablePartyGovernance gov) {
        defaultGovernanceOpts.totalVotingPower = totalVotingPower;
        return
            new TestablePartyGovernance(
                globals,
                defaultGovernanceOpts,
                preciousTokens,
                preciousTokenIds
            );
    }

    function _createProposal(
        uint256 numSteps
    ) private view returns (PartyGovernance.Proposal memory prop) {
        return
            PartyGovernance.Proposal({
                // Expires right after execution delay.
                maxExecutableTime: uint40(block.timestamp) +
                    defaultGovernanceOpts.executionDelay +
                    1,
                cancelDelay: uint40(1 days),
                proposalData: abi.encode(numSteps)
            });
    }

    function _getRandomDefaultHost() private view returns (address) {
        return defaultGovernanceOpts.hosts[_randomUint256() % defaultGovernanceOpts.hosts.length];
    }

    function _expectProposedEvent(
        uint256 proposalId,
        address proposer,
        PartyGovernance.Proposal memory proposal
    ) private {
        _expectEmit1();
        emit Proposed(proposalId, proposer, proposal);
    }

    function _expectProposalAcceptedEvent(
        uint256 proposalId,
        address voter,
        uint256 votingPower
    ) private {
        _expectEmit1();
        emit ProposalAccepted(proposalId, voter, votingPower);
    }

    function _expectProposalPassedEvent(uint256 proposalId) private {
        _expectEmit1();
        emit ProposalPassed(proposalId);
    }

    function _expectProposalExecutedEvent(
        uint256 proposalId,
        address executor,
        bytes memory nextProgressData
    ) private {
        _expectEmit1();
        emit ProposalExecuted(proposalId, executor, nextProgressData);
    }

    function _expectCompletedProposalExecutedEvent(uint256 proposalId, address executor) private {
        _expectEmit1();
        emit ProposalExecuted(proposalId, executor, "");
    }

    function _expectHostStatusTransferredEvent(address oldHost, address newHost) private {
        _expectEmit0();
        emit HostStatusTransferred(oldHost, newHost);
    }

    function _assertProposalStatusEq(
        TestablePartyGovernance gov,
        uint256 proposalId,
        PartyGovernance.ProposalStatus expected
    ) private {
        assertEq(uint256(gov.getProposalStatus(proposalId)), uint256(expected));
    }

    // One undelegated voter with 51/100 intrinsic VP.
    // One step proposal.
    function testProposalLifecycle_oneVoter() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Invalid);

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        _expectProposedEvent(proposalId, undelegatedVoter, proposal);
        // Votes are automatically cast by proposer.
        _expectProposalAcceptedEvent(proposalId, undelegatedVoter, 51e18);
        // Voter has majority VP so it also passes immediately.
        _expectProposalPassedEvent(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Passed);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Ready);

        // Execute the proposal as the single voter.
        _expectEmit0();
        emit DummyProposalExecutionEngine_executeCalled(
            address(gov),
            true,
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: proposalId,
                proposalData: proposal.proposalData,
                progressData: "",
                extraData: bytes("foo"),
                flags: 0,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds
            })
        );
        _expectCompletedProposalExecutedEvent(proposalId, undelegatedVoter);
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", bytes("foo"));

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Complete);
    }

    // One undelegated voter with 51/100 intrinsic VP.
    // Two step proposal.
    function testProposalLifecycle_oneVoter_twoStep() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a two-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(2);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        _expectProposedEvent(proposalId, undelegatedVoter, proposal);
        // Votes are automatically cast by proposer.
        _expectProposalAcceptedEvent(proposalId, undelegatedVoter, 51e18);
        // Voter has majority VP so it also passes immediately.
        _expectProposalPassedEvent(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);
        // Execute the proposal as the single voter. (1/2)
        _expectEmit0();
        emit DummyProposalExecutionEngine_executeCalled(
            address(gov),
            false,
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: proposalId,
                proposalData: proposal.proposalData,
                progressData: "",
                extraData: bytes("foo"),
                flags: 0,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds
            })
        );
        _expectProposalExecutedEvent(proposalId, undelegatedVoter, abi.encode(1));
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", bytes("foo"));

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.InProgress);

        // Execute the proposal as the single voter. (2/2)
        _expectEmit0();
        emit DummyProposalExecutionEngine_executeCalled(
            address(gov),
            true,
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: proposalId,
                proposalData: proposal.proposalData,
                progressData: abi.encode(1),
                extraData: bytes("bar"),
                flags: 0,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds
            })
        );
        _expectCompletedProposalExecutedEvent(proposalId, undelegatedVoter);
        vm.prank(undelegatedVoter);
        gov.execute(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            abi.encode(1),
            bytes("bar")
        );

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Complete);
    }

    // One undelegated voter with 100/100 intrinsic VP.
    // One step proposal.
    function testProposalLifecycle_oneVoterUnanimous() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 100/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 100e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        _expectProposedEvent(proposalId, undelegatedVoter, proposal);
        // Votes are automatically cast by proposer.
        _expectProposalAcceptedEvent(proposalId, undelegatedVoter, 100e18);
        // Voter has majority VP so it also passes immediately.
        _expectProposalPassedEvent(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);
        // The vote was unanimous so the proposal should be executable as well.
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Ready);

        // Execute the proposal as the single voter.
        _expectEmit0();
        emit DummyProposalExecutionEngine_executeCalled(
            address(gov),
            true,
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: proposalId,
                proposalData: proposal.proposalData,
                progressData: "",
                extraData: "",
                // Should be flagged unanimous.
                flags: LibProposal.PROPOSAL_FLAG_UNANIMOUS,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds
            })
        );
        _expectCompletedProposalExecutedEvent(proposalId, undelegatedVoter);
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
    }

    // One undelegated voter with 75/100 intrinsic VP.
    // One undelegated voter with 25/100 intrinsic VP.
    // One step proposal.
    function testProposalLifecycle_twoVotersUnanimous() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter1 = _randomAddress();
        address undelegatedVoter2 = _randomAddress();
        // undelegatedVoter1 has 75/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter1, 75e18, address(0));
        // undelegatedVoter2 has 25/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter2, 25e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter 1 submits proposal.
        _expectProposedEvent(proposalId, undelegatedVoter1, proposal);
        // Votes are automatically cast by proposer.
        _expectProposalAcceptedEvent(proposalId, undelegatedVoter1, 75e18);
        // Voter has majority VP so it also passes immediately.
        _expectProposalPassedEvent(proposalId);
        vm.prank(undelegatedVoter1);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Undelegated voter 2 votes.
        _expectProposalAcceptedEvent(proposalId, undelegatedVoter2, 25e18);
        vm.prank(undelegatedVoter2);
        gov.accept(proposalId, 0);
        // The vote was unanimous so the proposal should be executable as well.
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Ready);

        // Execute the proposal as the single voter.
        _expectEmit0();
        emit DummyProposalExecutionEngine_executeCalled(
            address(gov),
            true,
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: proposalId,
                proposalData: proposal.proposalData,
                progressData: "",
                extraData: "",
                // Should be flagged unanimous.
                flags: LibProposal.PROPOSAL_FLAG_UNANIMOUS,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds
            })
        );
        _expectCompletedProposalExecutedEvent(proposalId, undelegatedVoter1);
        vm.prank(undelegatedVoter1);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
    }

    // 99.99% acceptance counts as unanimous.
    function testProposalLifecycle_9999BpsIsUnanimous() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 99.99% of total voting supply.
        uint256 vp = (100e18 * 0.9999e4) / 1e4;
        gov.rawAdjustVotingPower(undelegatedVoter, int192(uint192(vp)), address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        _expectProposedEvent(proposalId, undelegatedVoter, proposal);
        // Votes are automatically cast by proposer.
        _expectProposalAcceptedEvent(proposalId, undelegatedVoter, vp);
        // Voter has majority VP so it also passes immediately.
        _expectProposalPassedEvent(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);
        // The vote was unanimous so the proposal should be executable as well.
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Ready);

        // Execute the proposal as the single voter.
        _expectEmit0();
        emit DummyProposalExecutionEngine_executeCalled(
            address(gov),
            true,
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: proposalId,
                proposalData: proposal.proposalData,
                progressData: "",
                extraData: "",
                // Should be flagged unanimous.
                flags: LibProposal.PROPOSAL_FLAG_UNANIMOUS,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds
            })
        );
        _expectCompletedProposalExecutedEvent(proposalId, undelegatedVoter);
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
    }

    // Try to execute a proposal that hasn't passed.
    function testProposalLifecycle_cannotExecuteWithoutPassing() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 50e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Try to execute proposal (fail).
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Voting
            )
        );
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);
        // Try again (fail).
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Voting
            )
        );
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
    }

    // Try to execute a proposal before the execution delay has passed.
    function testProposalLifecycle_cannotExecuteBeforeExecutionDelay() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        _expectProposalPassedEvent(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Try to execute proposal (fail).
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Passed
            )
        );
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
    }

    // Try to execute a proposal after its maxExecutableTime.
    function testProposalLifecycle_cannotExecuteAfterExpiration() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        _expectProposalPassedEvent(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Skip past the proposal expiration.
        vm.warp(proposal.maxExecutableTime + 1);

        // Try to execute proposal (fail).
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.ExecutionTimeExceededError.selector,
                proposal.maxExecutableTime,
                uint40(block.timestamp)
            )
        );
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
    }

    // Try to execute a proposal that has already completed.
    function testProposalLifecycle_cannotExecuteCompletedProposal() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        _expectProposalPassedEvent(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        // Execute (1/1).
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Complete);

        // Try to execute again.
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Complete
            )
        );
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
    }

    // Try to execute a proposal that has been modified.
    function testProposalLifecycle_cannotExecuteIfModified() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        _expectProposalPassedEvent(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        // Try to execute proposal (fail).
        bytes32 expectedHash = gov.getProposalHash(proposal);
        proposal.proposalData = bytes("naughty");
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalHashError.selector,
                gov.getProposalHash(proposal),
                expectedHash
            )
        );
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
    }

    function testProposalLifecycle_cannotCancelBeforeMinCancelTime() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address voter = _randomAddress();
        // voter has 100% intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(voter, 100e18, address(0));

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Create a two-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(2);
        uint256 proposalId = gov.getNextProposalId();
        // Propose and pass it.
        vm.prank(voter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Execute it.
        skip(defaultGovernanceOpts.executionDelay);
        vm.prank(voter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.InProgress);

        // Skip to just before cancel time.
        skip(proposal.cancelDelay - 1);
        // Try to cancel it (fail).
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.ProposalCannotBeCancelledYetError.selector,
                uint40(block.timestamp),
                uint40(block.timestamp + 1)
            )
        );
        vm.prank(voter);
        gov.cancel(proposalId, proposal);
    }

    function testProposalLifecycle_canCancel() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address voter = _randomAddress();
        // voter has 100% intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(voter, 100e18, address(0));

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Create a two-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(2);
        uint256 proposalId = gov.getNextProposalId();
        // Propose and pass it.
        vm.prank(voter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Execute it.
        skip(defaultGovernanceOpts.executionDelay);
        vm.prank(voter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.InProgress);

        // Skip to cancel time.
        skip(proposal.cancelDelay);
        // Cancel it.
        _expectEmit0();
        emit DummyProposalExecutionEngine_cancelCalled(address(gov), proposalId);
        _expectEmit1();
        emit ProposalCancelled(proposalId);
        vm.prank(voter);
        gov.cancel(proposalId, proposal);
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Cancelled);
    }

    function testProposalLifecycle_boundedByGlobalMaxCancelTime() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address voter = _randomAddress();
        // voter has 100% intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(voter, 100e18, address(0));

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Create a two-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(2);
        uint256 proposalId = gov.getNextProposalId();
        // Propose and pass it.
        vm.prank(voter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Execute it.
        skip(defaultGovernanceOpts.executionDelay);
        vm.prank(voter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.InProgress);

        // Set a global upper bound on the cancel time right before the proposal's cancelDelay.
        globals.setUint256(
            LibGlobals.GLOBAL_PROPOSAL_MAX_CANCEL_DURATION,
            proposal.cancelDelay - 1
        );

        // Skip to global max cancel time.
        skip(proposal.cancelDelay - 1);
        // Cancel it.
        _expectEmit0();
        emit DummyProposalExecutionEngine_cancelCalled(address(gov), proposalId);
        _expectEmit1();
        emit ProposalCancelled(proposalId);
        vm.prank(voter);
        gov.cancel(proposalId, proposal);
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Cancelled);
    }

    // only host can veto
    function testProposalLifecycle_onlyHostCanVeto() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 50e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal and votes, but does not have enough
        // to pass on their own.
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Non-host tries to veto.
        vm.expectRevert(abi.encodeWithSelector(PartyGovernance.OnlyPartyHostError.selector));
        vm.prank(undelegatedVoter);
        gov.veto(proposalId);
    }

    // cannot veto invalid proposal
    function testProposalLifecycle_cannotVetoInvalidProposal() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 50e18, address(0));

        uint256 proposalId = gov.getNextProposalId();
        address host = _getRandomDefaultHost();
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Invalid
            )
        );
        vm.prank(host);
        gov.veto(proposalId);
    }

    // can veto a proposal that's in vote.
    function testProposalLifecycle_canVetoVotingProposal() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 50e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal and votes, but does not have enough
        // to pass on their own.
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Voting);

        // Host vetos.
        address host = _getRandomDefaultHost();
        vm.prank(host);
        gov.veto(proposalId);

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Defeated);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        // Fails to execute.
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Defeated
            )
        );
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
    }

    // can veto a proposal that's ready.
    function testProposalLifecycle_canVetoReadyProposal() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        _expectProposalPassedEvent(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Ready);

        // Host vetos.
        address host = _getRandomDefaultHost();
        vm.prank(host);
        gov.veto(proposalId);

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Defeated);

        // Fails to execute.
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Defeated
            )
        );
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
    }

    // try to veto a proposal that's in progress.
    function testProposalLifecycle_cannotVetoInProgressProposal() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a two-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(2);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        _expectProposalPassedEvent(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        // Execute (1/2)
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");

        // Host tries to veto.
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.InProgress
            )
        );
        vm.prank(_getRandomDefaultHost());
        gov.veto(proposalId);
    }

    // try to veto a proposal that's completed.
    function testProposalLifecycle_cannotVetoCompleteProposal() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        _expectProposalPassedEvent(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        // Execute (1/1)
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");

        // Host tries to veto.
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Complete
            )
        );
        vm.prank(_getRandomDefaultHost());
        gov.veto(proposalId);
    }

    // An InProgress proposal that has expired is still executable.
    function testProposalLifecycle_canStillExecuteExpiredInProgressProposal() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Create a two-step proposal.
        // By default the proposal expires 1 second after the executable delay.
        PartyGovernance.Proposal memory proposal = _createProposal(2);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        // Voter has majority VP so it also passes immediately.
        _expectProposalPassedEvent(proposalId);
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Skip past execution delay.
        skip(defaultGovernanceOpts.executionDelay);

        // Execute (1/2)
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");

        // Skip past the proposal's maxExecutableTime.
        vm.warp(proposal.maxExecutableTime + 1);
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.InProgress);

        // Execute (2/2)
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, abi.encode(1), "");
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Complete);
    }

    // Try to execute a proposal after the voting window has expired and it has not passed.
    function testProposalLifecycle_cannotExecuteIfVotingWindowExpired() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        defaultGovernanceOpts.executionDelay = 60;
        defaultGovernanceOpts.voteDuration = 61;
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 50e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal.
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Voting);

        // Skip past voting window.
        skip(defaultGovernanceOpts.voteDuration);

        // Try to execute proposal (fail).
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Defeated
            )
        );
        vm.prank(undelegatedVoter);
        gov.execute(proposalId, proposal, preciousTokens, preciousTokenIds, "", "");
    }

    // One undelegated voter with 25/100 intrinsic VP.
    // One delegated voter with 25/100 intrinsic VP
    // One delegate with 25/100 intrinsic + 25 delegated VP.
    function testVoting_passing_mixedVotes() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate = _randomAddress();
        address delegatedVoter = _randomAddress();
        address undelegatedVoter = _randomAddress();
        // delegate has 25 intrinsic VP (delegated to no one/self), 25 delegated VP.
        gov.rawAdjustVotingPower(delegate, 25e18, address(0)); // self-delegated
        // delegatedVoter has 25 intrinsic VP (delegated to delegate)
        gov.rawAdjustVotingPower(delegatedVoter, 25e18, delegate);
        // undelegatedVoter has 25 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 25e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Delegated voter submits proposal.
        // No intrinsic or delegated votes so no vote cast during proposal.
        _expectProposalAcceptedEvent(proposalId, delegatedVoter, 0);
        vm.prank(delegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Voting);

        // Undelegated (self-delegated) voter votes.
        _expectProposalAcceptedEvent(proposalId, undelegatedVoter, 25e18);
        vm.prank(undelegatedVoter);
        gov.accept(proposalId, 0);

        // Delegate votes with delegated and intrinsic voting power.
        _expectProposalAcceptedEvent(proposalId, delegate, 50e18);
        // Combined, votes are enough (75%) to push it over the pass threshold (50%).
        _expectProposalPassedEvent(proposalId);
        vm.prank(delegate);
        gov.accept(proposalId, 0);

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Passed);
    }

    // One undelegated voter with 10/100 intrinsic VP.
    // One delegated voter with 10/100 intrinsic VP
    // One delegate with 30/100 intrinsic + 10 delegated VP.
    // Combined 10 + 10 + 30 -> 50 < 51 (no pass)
    function testVoting_notPassing_mixedVotes() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate = _randomAddress();
        address delegatedVoter = _randomAddress();
        address undelegatedVoter = _randomAddress();
        // delegate has 30 intrinsic VP (delegated to no one/self), 10 delegated VP.
        gov.rawAdjustVotingPower(delegate, 30e18, address(0)); // self-delegated
        // delegatedVoter has 10 intrinsic VP (delegated to delegate)
        gov.rawAdjustVotingPower(delegatedVoter, 10e18, delegate);
        // undelegatedVoter has 10 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 10e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Delegated voter submits proposal.
        // No intrinsic or delegated votes so no vote cast during proposal.
        emit ProposalAccepted(proposalId, delegatedVoter, 0);
        vm.prank(delegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Undelegated (self-delegated) voter votes.
        _expectProposalAcceptedEvent(proposalId, undelegatedVoter, 10e18);
        vm.prank(undelegatedVoter);
        gov.accept(proposalId, 0);

        // Delegate votes with delegated and intrinsic voting power.
        _expectProposalAcceptedEvent(proposalId, delegate, 40e18);
        vm.prank(delegate);
        gov.accept(proposalId, 0);

        // 10 + 10 + 30 = 50, but need 51/100 to pass.
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Voting);
    }

    // Try to vote outside the voting window.
    function testVoting_cannotVoteOutsideVotingWindow() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter1 = _randomAddress();
        address undelegatedVoter2 = _randomAddress();
        // undelegatedVoter1 has 50/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter1, 50e18, address(0));
        // undelegatedVoter2 has 1/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter2, 1e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter 1 submits proposal (and votes).
        vm.prank(undelegatedVoter1);
        assertEq(gov.propose(proposal, 0), proposalId);

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Voting);

        // Skip past voting window.
        skip(defaultGovernanceOpts.voteDuration);

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Defeated);

        // Undelegated voter 2 tries to vote.
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Defeated
            )
        );
        vm.prank(undelegatedVoter2);
        gov.accept(proposalId, 0);
    }

    // Try to vote twice (undelegated voter)
    function testVoting_cannotVoteTwice() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter, 50e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter submits proposal (and votes).
        vm.prank(undelegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Try to vote again.
        vm.expectRevert(
            abi.encodeWithSelector(PartyGovernance.AlreadyVotedError.selector, undelegatedVoter)
        );
        vm.prank(undelegatedVoter);
        gov.accept(proposalId, 0);
    }

    // Try to vote twice (delegate)
    function testVoting_delegateCannotVoteTwice() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate = _randomAddress();
        address delegatedVoter = _randomAddress();
        // delegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(delegatedVoter, 50e18, delegate);

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Delegate submits proposal (and votes).
        vm.prank(delegate);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Try to vote again.
        vm.expectRevert(
            abi.encodeWithSelector(PartyGovernance.AlreadyVotedError.selector, delegate)
        );
        vm.prank(delegate);
        gov.accept(proposalId, 0);
    }

    // Try to vote twice (delegated voter)
    function testVoting_delegatedVoterCannotVoteTwice() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate = _randomAddress();
        address delegatedVoter = _randomAddress();
        // delegatedVoter has 50/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(delegatedVoter, 50e18, delegate);

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Delegated voter submits proposal (and votes).
        vm.prank(delegatedVoter);
        assertEq(gov.propose(proposal, 0), proposalId);

        // Try to vote again.
        vm.expectRevert(
            abi.encodeWithSelector(PartyGovernance.AlreadyVotedError.selector, delegatedVoter)
        );
        vm.prank(delegatedVoter);
        gov.accept(proposalId, 0);
    }

    // Try to vote on a vetoed proposal.
    function testVoting_cannotVoteAfterVeto() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter1 = _randomAddress();
        address undelegatedVoter2 = _randomAddress();
        // undelegatedVoter1 has 50/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter1, 50e18, address(0));
        // undelegatedVoter2 has 1/100 intrinsic VP (delegated to no one/self)
        gov.rawAdjustVotingPower(undelegatedVoter2, 50e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Undelegated voter 1 submits proposal (and votes).
        vm.prank(undelegatedVoter1);
        assertEq(gov.propose(proposal, 0), proposalId);

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Voting);

        // Host vetos.
        address host = _getRandomDefaultHost();
        _expectEmit1();
        emit ProposalVetoed(proposalId, host);
        vm.prank(host);
        gov.veto(proposalId);

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Defeated);

        // Undelegated voter 2 tries to vote.
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernance.BadProposalStatusError.selector,
                PartyGovernance.ProposalStatus.Defeated
            )
        );
        vm.prank(undelegatedVoter2);
        gov.accept(proposalId, 0);
    }

    // Vote using VP from proposal time.
    function testVoting_votingUsesProposalTimeVotingPower() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate = _randomAddress();
        address undelegatedVoter = _randomAddress();
        address delegatedVoter = _randomAddress();
        address proposer = _randomAddress();
        // proposer has 1 wei of intrinsic VP (just enough to propose), delegated to
        // an address we won't use.
        gov.rawAdjustVotingPower(proposer, 1, address(0xbadb01));
        // delegate has 30 intrinsic, 50 delegated VP
        gov.rawAdjustVotingPower(delegate, 30e18, address(0));
        // delegatedVoter has 20 intrinsic delegated to delegate.
        gov.rawAdjustVotingPower(delegatedVoter, 20e18, delegate);
        // undelegatedVoter has 1 intrinsing VP, delegated to no one/self.
        gov.rawAdjustVotingPower(undelegatedVoter, 1e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // Propose it from proposer, locking in the proposal time
        // and not casting any votes because proposer has delegated to
        // someone else.
        vm.prank(proposer);
        assertEq(gov.propose(proposal, 0), proposalId);

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
        _expectProposalAcceptedEvent(
            proposalId,
            undelegatedVoter,
            1e18 // Proposal time VP.
        );
        vm.prank(undelegatedVoter);
        gov.accept(proposalId, 0);

        // delegatedVoter will vote, who does not have any VP now and also had
        // no VP at proposal time.
        _expectProposalAcceptedEvent(
            proposalId,
            delegatedVoter,
            0 // Proposal time VP.
        );
        vm.prank(delegatedVoter);
        gov.accept(proposalId, 0);

        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Voting);

        // Delegate will vote, who does not have any VP now but at proposal time
        // had a total of 50, which will make the proposal pass.
        _expectProposalAcceptedEvent(
            proposalId,
            delegate,
            50e18 // Proposal time VP.
        );
        _expectProposalPassedEvent(proposalId);
        vm.prank(delegate);
        gov.accept(proposalId, 0);
    }

    function testVoting_cannotVoteAgainByTransferringVotingCard() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        // Give voter 30 intrinsic VP.
        address voter = _randomAddress();
        gov.rawAdjustVotingPower(voter, 30e18, address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();
        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        _expectProposalAcceptedEvent(proposalId, voter, 30e18);
        vm.prank(voter);
        gov.propose(proposal, 0);

        // Transfer VP to another wallet.
        address anotherWallet = _randomAddress();
        gov.transferVotingPower(voter, anotherWallet, 30e18);

        // Assert that this does not increase votes (proposal was accepted with 0 VP)
        // because voting power queried from the past
        _expectProposalAcceptedEvent(proposalId, anotherWallet, 0);
        vm.prank(anotherWallet);
        gov.accept(proposalId, 0);
    }

    // Circular delegation.
    function testVoting_circularDelegation() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate1 = _randomAddress();
        address delegate2 = _randomAddress();
        // Set up circular delegation just to be extra tricky.
        // delegate has 1 intrinsic, 51 delegated VP
        gov.rawAdjustVotingPower(delegate1, 1e18, delegate2);
        // delegate2 has 50 intrinsic, 1 delegated VP
        gov.rawAdjustVotingPower(delegate2, 50e18, delegate1);

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // delegate2 proposes and votes with their 1 effective VP.
        _expectProposalAcceptedEvent(proposalId, delegate2, 1e18);
        vm.prank(delegate2);
        gov.propose(proposal, 0);

        assertEq(uint256(gov.getVotes(proposalId)), 1e18);

        // delegate1 votes with their 50 effective VP.
        _expectProposalAcceptedEvent(proposalId, delegate1, 50e18);
        // With 51 total, the proposal will pass.
        _expectProposalPassedEvent(proposalId);
        vm.prank(delegate1);
        gov.accept(proposalId, 0);

        assertEq(uint256(gov.getVotes(proposalId)), 51e18);
    }

    // Cannot adjust voting power below 0.
    function testVotingPower_cannotAdjustVotingPowerBelowZero() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address undelegatedVoter = _randomAddress();
        // undelegatedVoter has 51 intrinsic VP
        gov.rawAdjustVotingPower(undelegatedVoter, 51e18, address(0));

        // Try to adjust below 0.
        vm.expectRevert(
            abi.encodeWithSelector(LibSafeCast.Int192ToUint96CastOutOfRange.selector, int192(-1))
        );
        gov.rawAdjustVotingPower(undelegatedVoter, -51e18 - 1, address(0));
    }

    function testVotingPower_getVotingPowerWithValidHint() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address voter = _randomAddress();

        // voter has 50 intrinsic VP at snapshot index 0
        skip(10);
        gov.rawAdjustVotingPower(voter, 50e18, address(0));

        assertEq(gov.findVotingPowerSnapshotIndex(voter, uint40(block.timestamp)), 0);
        assertEq(gov.getVotingPowerAt(voter, uint40(block.timestamp), 0), 50e18);
    }

    function testVotingPower_getVotingPowerWithInvalidHint() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address voter = _randomAddress();
        // voter has 50 intrinsic VP at snapshot index 0
        gov.rawAdjustVotingPower(voter, 50e18, address(0));
        skip(10);
        // voter has 100 intrinsic VP at snapshot index 1
        gov.rawAdjustVotingPower(voter, 50e18, address(0));

        uint40 timestamp = uint40(block.timestamp);

        // snapshot index is before latest snapshot at `timestamp`, should
        // fallback to `findVotingPowerSnapshotIndex` to find and return correct
        // snapshot
        assertEq(gov.getVotingPowerAt(voter, timestamp, 0), 100e18);
        assertEq(gov.findVotingPowerSnapshotIndex(voter, timestamp), 1);

        // voter has 150 intrinsic VP at snapshot index 2
        skip(10);
        gov.rawAdjustVotingPower(voter, 50e18, address(0));

        // snapshot index is ahead of latest snapshot at `timestamp`, should
        // fallback to `findVotingPowerSnapshotIndex` to find and return correct
        // snapshot
        assertEq(gov.getVotingPowerAt(voter, timestamp, 0), 100e18);
        assertEq(gov.findVotingPowerSnapshotIndex(voter, timestamp), 1);
    }

    function testVotingPower_getVotingPowerWithHintAboveSnapshotsLength() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address voter = _randomAddress();

        // voter has 50 intrinsic VP at snapshot index 0
        skip(10);
        gov.rawAdjustVotingPower(voter, 50e18, address(0));

        assertEq(gov.getVotingPowerAt(voter, uint40(block.timestamp), type(uint256).max), 50e18);
        assertEq(gov.findVotingPowerSnapshotIndex(voter, uint40(block.timestamp)), 0);
    }

    function testVotingPower_getVotingPowerWithNoSnapshots() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address voter = _randomAddress();

        // no snapshots, should return 0 voting power
        assertEq(gov.getVotingPowerAt(voter, uint40(block.timestamp), 0), 0);
        assertEq(
            gov.findVotingPowerSnapshotIndex(voter, uint40(block.timestamp)),
            type(uint256).max
        );
    }

    function testVotingPower_findVotingPowerSnapshotIndex() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address voter = _randomAddress();

        // voter has no voting power snapshots
        assertEq(
            gov.findVotingPowerSnapshotIndex(voter, uint40(block.timestamp)),
            type(uint256).max
        );

        // 30s ago (no voting power)
        skip(10);
        // 20s ago
        gov.rawAdjustVotingPower(voter, 1, address(0));
        skip(10);
        // 10s ago
        gov.rawAdjustVotingPower(voter, 1, address(0));
        skip(10);
        // 0s ago
        gov.rawAdjustVotingPower(voter, 1, address(0));

        uint40 timestamp = uint40(block.timestamp);

        // 0s ago
        assertEq(gov.findVotingPowerSnapshotIndex(voter, timestamp), 2);
        // 5s ago
        assertEq(gov.findVotingPowerSnapshotIndex(voter, timestamp - 5), 1);
        // 15s ago
        assertEq(gov.findVotingPowerSnapshotIndex(voter, timestamp - 15), 0);
        // 25s ago
        assertEq(gov.findVotingPowerSnapshotIndex(voter, timestamp - 25), type(uint256).max);
    }

    // _adjustVotingPower() updates delegated VP correctly
    function testVotingPower_adjustVotingPowerUpdatesDelegatesCorrectly() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address delegate1 = _randomAddress();
        address delegate2 = _randomAddress();
        address voter = _randomAddress();
        // voter has 50 intrinsic VP, delegated to delegate1.
        gov.rawAdjustVotingPower(voter, 50e18, delegate1);
        // delegate1 has 10 intrinsic VP, delegated to delegate2.
        gov.rawAdjustVotingPower(delegate1, 10e18, delegate2);
        // delegate2 has 20 intrinsic VP, delegated to self.
        gov.rawAdjustVotingPower(delegate2, 20e18, address(0));

        // Remove 5 intrinsic VP from voter and redelegate to delegate2.
        gov.rawAdjustVotingPower(voter, -5e18, delegate2);
        // Add 5 intrinsic VP to delegate1 and keep delegation to delegate2.
        gov.rawAdjustVotingPower(delegate1, 5e18, delegate2);
        // Remove 3 intrinsic VP from delegate1 and keep delegation to delegate2.
        gov.rawAdjustVotingPower(delegate1, -3e18, delegate2);
        // Redelegate delegate2 to delegate1.
        gov.rawAdjustVotingPower(delegate2, 0, delegate1);

        // Now check total VPs.
        // voter: 50 - 5 = 45 intrinsic (delegated: delegate2) + 0 delegated -> 0
        assertEq(uint256(gov.getVotingPowerAt(voter, uint40(block.timestamp), 0)), 0);
        // delegate1: 10 + 5 - 3 = 12 intrinsic (delegated: delegate2) + 20 delegated -> 20
        assertEq(uint256(gov.getVotingPowerAt(delegate1, uint40(block.timestamp), 0)), 20e18);
        // delegate2: 20 intrinsic (delegated: deleate1) + 45 + 12 = 57 delegated -> 57
        assertEq(uint256(gov.getVotingPowerAt(delegate2, uint40(block.timestamp), 0)), 57e18);

        // Check internal accounting for voter.
        {
            PartyGovernance.VotingPowerSnapshot memory snap = gov.getVotingPowerSnapshotAt(
                voter,
                block.timestamp,
                0
            );
            assertEq(uint256(snap.intrinsicVotingPower), 45e18);
            assertEq(uint256(snap.delegatedVotingPower), 0);
        }
        // Check internal accounting for delegate1.
        {
            PartyGovernance.VotingPowerSnapshot memory snap = gov.getVotingPowerSnapshotAt(
                delegate1,
                block.timestamp,
                0
            );
            assertEq(uint256(snap.intrinsicVotingPower), 12e18);
            assertEq(uint256(snap.delegatedVotingPower), 20e18);
        }
        // Check internal accounting for delegate2.
        {
            PartyGovernance.VotingPowerSnapshot memory snap = gov.getVotingPowerSnapshotAt(
                delegate2,
                block.timestamp,
                0
            );
            assertEq(uint256(snap.intrinsicVotingPower), 20e18);
            assertEq(uint256(snap.delegatedVotingPower), 57e18);
        }
    }

    // delegate(self) == delegate(0) if no prior delegate
    function testVotingPower_delegateSelfIsSameAsDelegateZero() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address voter1 = _randomAddress();
        address voter2 = _randomAddress();
        // voter has 50 intrinsic VP, delegated to zero.
        gov.rawAdjustVotingPower(voter1, 50e18, address(0));
        // voter has 25 intrinsic VP, delegated to self.
        gov.rawAdjustVotingPower(voter2, 25e18, voter2);

        assertEq(gov.getVotingPowerAt(voter1, uint40(block.timestamp), 0), 50e18);
        assertEq(gov.getVotingPowerAt(voter2, uint40(block.timestamp), 0), 25e18);

        // Now flip it via delegateVotingPower()
        vm.prank(voter1);
        gov.delegateVotingPower(voter1);
        vm.prank(voter2);
        gov.delegateVotingPower(address(0));

        assertEq(gov.getVotingPowerAt(voter1, uint40(block.timestamp), 0), 50e18);
        assertEq(gov.getVotingPowerAt(voter2, uint40(block.timestamp), 0), 25e18);
    }

    // Hosts can transfer their host status to another address
    function testHostPower_transferHostStatus() external {
        TestablePartyGovernance gov;
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);

        address newHost = _randomAddress();

        // Transfer host status to another address
        address host = _getRandomDefaultHost();
        vm.prank(host);
        _expectHostStatusTransferredEvent(host, newHost);
        gov.abdicate(newHost);

        // Assert old host is no longer host
        assertEq(gov.isHost(host), false);

        // Assert new host is host
        assertEq(gov.isHost(newHost), true);
    }

    // You cannot transfer host status to an existing host
    function testHostPower_cannotTransferHostStatusToExistingHost() external {
        TestablePartyGovernance gov;
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);

        address host = _getRandomDefaultHost();

        // try to transfer host status to an existing host
        vm.prank(host);
        vm.expectRevert(abi.encodeWithSelector(PartyGovernance.InvalidNewHostError.selector));
        gov.abdicate(host);
    }

    // Cannot transfer host status as a non-host
    function testHostPower_cannotTransferHostAsNonHost() external {
        TestablePartyGovernance gov;
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);

        address nonHost = _randomAddress();
        address nonHost2 = _randomAddress();

        vm.prank(nonHost);
        vm.expectRevert(abi.encodeWithSelector(PartyGovernance.OnlyPartyHostError.selector));
        gov.abdicate(nonHost2);
    }

    // voting power of past member is 0 at current time.
    function testVotingPower_votingPowerOfPastMemberIsZeroAtCurrentTime() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address pastMember = _randomAddress();
        // Used to have VP.
        gov.rawAdjustVotingPower(pastMember, 50e18, address(0));

        skip(1);
        // pastMember loses all their voting power.
        gov.rawAdjustVotingPower(pastMember, -50e18, pastMember);
        assertEq(gov.getVotingPowerAt(pastMember, uint40(block.timestamp), 1), 0);
    }

    // voting power of never member is 0 at current time.
    function testVotingPower_votingPowerOfNeverMemberIsZeroAtCurrentTime() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        skip(1);
        address nonMember = _randomAddress();
        assertEq(gov.getVotingPowerAt(nonMember, uint40(block.timestamp), 1), 0);
    }

    // voting power of past member is nonzero at past time.
    function testVotingPower_votingPowerOfPastMemberIsNonZeroInPastTime() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address pastMember = _randomAddress();
        // Uesd to have VP.
        gov.rawAdjustVotingPower(pastMember, 50e18, address(0));

        // Move ahead 100 seconds.
        skip(100);
        // pastMember loses all their voting power.
        gov.rawAdjustVotingPower(pastMember, -50e18, pastMember);
        // 1 seconds ago pastMember still had original voting power.
        assertEq(gov.getVotingPowerAt(pastMember, uint40(block.timestamp - 2), 0), 50e18);
    }

    // voting power of past member is nonzero at past time.
    function testVotingPower_votingPowerOfAdjustedVoterAndDelegateIsCorrectAtDifferentTimes()
        external
    {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address voter1 = _randomAddress();
        address voter2 = _randomAddress();

        // 40s ago
        gov.rawAdjustVotingPower(voter1, 50e18, voter1);
        gov.rawAdjustVotingPower(voter2, 1, voter1);
        skip(10);
        // 30s ago
        // address(0) after initial minting reuses current chosen delegate
        gov.rawAdjustVotingPower(voter1, -50e18, address(0));
        skip(10);
        // 20s ago
        gov.rawAdjustVotingPower(voter1, 75e18, address(0));
        gov.rawAdjustVotingPower(voter2, 1, address(0));
        skip(10);
        // 10s ago
        gov.rawAdjustVotingPower(voter1, -10e18, voter2);
        skip(10);
        // 0s ago
        gov.rawAdjustVotingPower(voter1, -10e18, voter1);
        gov.rawAdjustVotingPower(voter2, -1, voter2);

        // 35s ago
        assertEq(gov.getVotingPowerAt(voter1, uint40(block.timestamp - 35), 0), 50e18 + 1);
        assertEq(gov.getVotingPowerAt(voter2, uint40(block.timestamp - 35), 0), 0);
        // 25s ago
        assertEq(gov.getVotingPowerAt(voter1, uint40(block.timestamp - 25), 1), 1);
        assertEq(gov.getVotingPowerAt(voter2, uint40(block.timestamp - 25), 0), 0);
        // 15s ago
        assertEq(gov.getVotingPowerAt(voter1, uint40(block.timestamp - 15), 2), 75e18 + 2);
        assertEq(gov.getVotingPowerAt(voter2, uint40(block.timestamp - 15), 1), 0);
        // 5s ago
        assertEq(gov.getVotingPowerAt(voter1, uint40(block.timestamp - 5), 3), 2);
        assertEq(gov.getVotingPowerAt(voter2, uint40(block.timestamp - 5), 2), 65e18);
        // 0s ago
        assertEq(gov.getVotingPowerAt(voter1, uint40(block.timestamp), 4), 55e18);
        assertEq(gov.getVotingPowerAt(voter2, uint40(block.timestamp), 3), 1);
    }

    // voting smoke test with random governance params.
    function testVotingPower_paramsSmokeTest() external {
        uint256 totalVotingPower = (100e18 * (_randomUint256() % 1e4)) / 1e4;
        assertTrue(totalVotingPower <= 100e18);
        uint256 passThresholdBps = (_randomUint256() % (1e4 - 1)) + 1;
        assertTrue(passThresholdBps <= 1e4);
        defaultGovernanceOpts.passThresholdBps = uint16(passThresholdBps);
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(
            uint96(totalVotingPower),
            preciousTokens,
            preciousTokenIds
        );

        address voter1 = _randomAddress();
        address voter2 = _randomAddress();
        // Rounded up.
        uint256 votesNeededToPass = (uint256(totalVotingPower) * passThresholdBps) / (1e4 - 1);
        assertTrue(votesNeededToPass < totalVotingPower);
        // voter1 has half the votes needed to pass.
        gov.rawAdjustVotingPower(voter1, int192(int256(votesNeededToPass / 2)), address(0));
        // voter has half + 1 the votes needed to pass.
        gov.rawAdjustVotingPower(voter2, int192(int256(votesNeededToPass / 2 + 1)), address(0));

        // Create a one-step proposal.
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        uint256 proposalId = gov.getNextProposalId();

        // Skip because `accept()` will query voting power at `proposedTime - 1`
        skip(1);
        // voter1 proposes and votes.
        vm.prank(voter1);
        gov.propose(proposal, 0);
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Voting);

        // voter2 votes, which gets it to pass.
        vm.prank(voter2);
        gov.accept(proposalId, 0);
        _assertProposalStatusEq(gov, proposalId, PartyGovernance.ProposalStatus.Passed);
    }

    // distribute ETH balance
    function testDistribute_worksWithEth() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);

        // Only a member with VP can call distribute().
        address member = _randomAddress();
        gov.rawAdjustVotingPower(member, 1e18, member);

        // Create a distribution.
        vm.deal(address(gov), 1337e18);
        _expectEmit0();
        emit DummyTokenDistributor_createDistributionCalled(
            gov,
            ITokenDistributor.TokenType.Native,
            ETH_ADDRESS,
            0,
            defaultGovernanceOpts.feeRecipient,
            defaultGovernanceOpts.feeBps,
            1337e18,
            tokenDistributor.lastId() + 1
        );
        vm.prank(member);
        gov.distribute(ITokenDistributor.TokenType.Native, ETH_ADDRESS, 0);
        assertEq(tokenDistributor.SINK().balance, 1337e18);
    }

    // distribute ERC20 balance
    function testDistribute_worksWithErc20() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);

        // Only a member with VP can call distribute().
        address member = _randomAddress();
        gov.rawAdjustVotingPower(member, 1e18, member);

        DummyERC20 erc20 = new DummyERC20();
        erc20.deal(address(gov), 1337e18);

        // Create a distribution.
        _expectEmit0();
        emit DummyTokenDistributor_createDistributionCalled(
            gov,
            ITokenDistributor.TokenType.Erc20,
            address(erc20),
            0,
            defaultGovernanceOpts.feeRecipient,
            defaultGovernanceOpts.feeBps,
            1337e18,
            tokenDistributor.lastId() + 1
        );
        vm.prank(member);
        gov.distribute(ITokenDistributor.TokenType.Erc20, address(erc20), 0);
        assertEq(erc20.balanceOf(tokenDistributor.SINK()), 1337e18);
    }

    // try to distribute from a no longer active member.
    function testDistribute_onlyActiveMemberCanDistribute() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);

        address member = _randomAddress();
        gov.rawAdjustVotingPower(member, 1e18, member);
        // Transfer all VP so they're no longer a member.
        skip(1);
        gov.rawAdjustVotingPower(member, -1e18, member);

        // Try to create a distribution.
        vm.deal(address(gov), 1337e18);
        vm.expectRevert(abi.encodeWithSelector(PartyGovernance.OnlyActiveMemberError.selector));
        vm.prank(member);
        gov.distribute(ITokenDistributor.TokenType.Native, ETH_ADDRESS, 0);
    }

    function test_onlyWhenNotDisabled() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        address member = _randomAddress();
        gov.rawAdjustVotingPower(member, 1, address(0));

        // Disable party actions.
        globals.setBool(LibGlobals.GLOBAL_DISABLE_PARTY_ACTIONS, true);

        // Try executing a proposal.
        vm.prank(member);
        vm.expectRevert(PartyGovernance.OnlyWhenEnabledError.selector);
        gov.execute(0, _createProposal(1), preciousTokens, preciousTokenIds, "", bytes("foo"));

        // Try creating a distribution.
        vm.prank(member);
        vm.expectRevert(PartyGovernance.OnlyWhenEnabledError.selector);
        gov.distribute(ITokenDistributor.TokenType.Native, ETH_ADDRESS, 0);
    }

    function test_canReceive1155Token() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);

        address owner = _randomAddress();
        DummyERC1155 erc1155 = new DummyERC1155();
        erc1155.deal(owner, 1337, 1e18);
        vm.prank(owner);
        erc1155.safeTransferFrom(owner, address(gov), 1337, 1e18, "");
    }

    function test_canReceive721Token() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);

        address owner = _randomAddress();
        DummyERC721 erc721 = new DummyERC721();
        uint256 id = erc721.mint(owner);
        vm.prank(owner);
        erc721.safeTransferFrom(owner, address(gov), id, "");
    }

    function test_getProposalHash_isCorrect() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        PartyGovernance.Proposal memory proposal = _createProposal(1);
        bytes32 expectedHash = keccak256(
            abi.encode(
                proposal.maxExecutableTime,
                proposal.cancelDelay,
                keccak256(proposal.proposalData)
            )
        );
        bytes32 actualHash = gov.testGetProposalHash(proposal);
        assertEq(actualHash, expectedHash);
    }

    function test_hashPreciousList() external {
        (
            IERC721[] memory preciousTokens,
            uint256[] memory preciousTokenIds
        ) = _createPreciousTokens(2);
        TestablePartyGovernance gov = _createGovernance(100e18, preciousTokens, preciousTokenIds);
        bytes32 expectedHash = keccak256(
            abi.encode(
                keccak256(abi.encode(preciousTokens[0], preciousTokens[1])),
                keccak256(abi.encode(preciousTokenIds[0], preciousTokenIds[1]))
            )
        );
        bytes32 actualHash = gov.hashPreciousList(preciousTokens, preciousTokenIds);
        assertEq(actualHash, expectedHash);
    }
}
