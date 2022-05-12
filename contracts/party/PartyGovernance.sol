// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../distribution/ITokenDistributorParty.sol";
import "../distribution/TokenDistributor.sol";
import "../utils/ReadOnlyDelegateCall.sol";
import "../tokens/IERC721.sol";
import "../tokens/IERC20.sol";
import "../utils/LibERC20Compat.sol";
import "../utils/LibRawResult.sol";
import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../proposals/IProposalExecutionEngine.sol";
import "../proposals/LibProposal.sol";

import "./IPartyFactory.sol";

// Base contract for a Party encapsulating all governance functionality.
contract PartyGovernance is
    ITokenDistributorParty,
    ReadOnlyDelegateCall
{
    using LibERC20Compat for IERC20;
    using LibRawResult for bytes;

    enum ProposalState {
        Invalid,
        Voting,
        Defeated,
        Passed,
        Ready,
        InProgress,
        Complete
    }

    struct GovernanceOpts {
        // Address of initial party hosts.
        address[] hosts;
        // How long people can vote on a proposal.
        uint40 voteDurationInSeconds;
        // How long to wait after a proposal passes before it can be
        // executed.
        uint40 executionDelayInSeconds;
        // Minimum ratio of accept votes to consider a proposal passed,
        // in bps, where 1000 == 100%.
        uint16 passThresholdBps;
        // Total voting power of governance NFTs.
        uint96 totalVotingPower;
    }

    // Subset of `GovernanceOpts` that are commonly needed together for
    // efficiency.
    struct GovernanceValues {
        // How long people can vote on a proposal.
        uint40 voteDurationInSeconds;
        // How long to wait after a proposal passes before it can be
        // executed.
        uint40 executionDelayInSeconds;
        // Minimum ratio of accept votes to consider a proposal passed,
        // in bps, where 1000 == 100%.
        uint16 passThresholdBps;
        // Total voting power of governance NFTs.
        uint96 totalVotingPower;
    }

    struct VotingPowerSnapshot {
        // The timestamp when the snapshot was taken.
        uint40 timestamp;
        // Voting power that was delegated to this user by others.
        uint96 delegatedVotingPower;
        // The intrinsic (not delegated from someone else) voting power of this user.
        uint96 intrinsicVotingPower;
        // Whether the user was delegated to another at this snapshot.
        bool isDelegated;
    }

    struct Proposal {
        uint40 maxExecutableTime;
        uint256 nonce;
        bytes proposalData;
    }

    // Fits in a word.
    struct ProposalInfoValues {
        // When the proposal was proposed.
        uint40 proposedTime;
        // When the proposal passed the vote.
        uint40 passedTime;
        // When the proposal was first executed.
        uint40 executedTime;
        // When the proposal completed.
        uint40 completedTime;
        // Number of accept votes.
        uint96 votes; // -1 == vetoed
    }

    struct ProposalInfo {
        ProposalInfoValues values;
        bytes32 hash;
        mapping (address => bool) hasVoted;
    }

    event Proposed(
        uint256 proposalId,
        address proposer,
        Proposal proposal
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
    event VotingPowerDelegated(address owner, address delegate, uint256 votingPower);

    error BadProposalStateError(ProposalState state);
    error ProposalExistsError(uint256 proposalId);
    error BadProposalHashError(bytes32 proposalHash, bytes32 actualHash);
    error ProposalHasNoVotesError(uint256 proposalId);
    error Int192ToUint96CastOutOfRange(int192 i192);
    error ExecutionTimeExceededError(uint40 maxExecutableTime, uint40 timestamp);
    error OnlyPartyHostError();
    error OnlyActiveMemberError();

    IGlobals private immutable _GLOBALS;

    GovernanceValues public governanceValues;
    // The contract of the NFT we're trying to protect.
    IERC721 public preciousToken;
    // The id of the NFT we're trying to protect.
    uint256 public preciousTokenId;
    // The last proposal ID that was used. 0 means no proposals have been made.
    uint256 public lastProposalId;
    // Whether an address is a party host.
    mapping(address => bool) public isHost;
    // The last person a voter delegated its voting power to.
    mapping(address => address) public delegationsByVoter;
    // ProposalInfo by proposal ID.
    mapping(uint256 => ProposalInfo) private _proposalInfoByProposalId;
    // Snapshots of voting power per user, each sorted by increasing time.
    mapping(address => VotingPowerSnapshot[]) private _votingPowerSnapshotsByVoter;

    modifier onlyHost() {
        if (!isHost[msg.sender]) {
            revert OnlyPartyHostError();
        }
        _;
    }

    modifier onlyActiveMember() {
        if (_getLastVotingPowerSnapshot(msg.sender).intrinsicVotingPower == 0) {
            revert OnlyActiveMemberError();
        }
        _;
    }

    constructor() {
        _GLOBALS = IPartyFactory(msg.sender)._GLOBALS();
    }

    function initialize(
        GovernanceOpts memory opts,
        IERC721 preciousToken,
        uint256 preciousTokenId
    )
        public
        virtual
    {
        LibProposal.initProposalImpl(IProposalExecutionEngine(
            _GLOBALS.getAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL)
        ));
        governanceValues = GovernanceValues({
            voteDurationInSeconds: opts.voteDurationInSeconds,
            executionDelayInSeconds: opts.executionDelayInSeconds,
            passThresholdBps: opts.passThresholdBps,
            totalVotingPower: opts.totalVotingPower
        });
        preciousToken = preciousToken;
        preciousTokenId = preciousTokenId;
    }

    fallback() external {
        // Forward all unknown read-only calls to the proposal execution engine.
        // Initial use case is to facilitate eip-1271 signatures.
        _readOnlyDelegateCall(
            address(LibProposal.getProposalExecutionEngine()),
            msg.data
        );
    }

    // Get the current IProposalExecutionEngine instance.
    function getProposalExecutionEngine()
        external
        view
        returns (address IProposalExecutionEngine)
    {
        return LibProposal.getProposalExecutionEngine();
    }

    // Get the total (delegated + intrinsic) voting power of `voter` by a timestamp.
    function getVotingPowerAt(address voter, uint40 timestamp)
        external
        view
        returns (uint96 votingPower)
    {
        VotingPowerSnapshot memory shot = _getVotingPowerSnapshotAt(voter, timestamp);
        return shot.intrinsicVotingPower + shot.delegatedVotingPower;
    }

    function getProposalStates(uint256 proposalId)
        external
        view
        returns (ProposalState state, ProposalInfoValues memory values)
    {
        values = _proposalInfoByProposalId[proposalId].values;
        state = _getProposalState(values);
    }

    // Pledge your intrinsic voting power to a new delegate, removing it from
    // the old one (if any).
    function delegateVotingPower(address delegate) external view returns (uint256)
    {
        address oldDelegate = delegationsByVoter[msg.sender];
        delegationsByVoter[msg.sender] = delegate;
        VotingPowerSnapshot memory snap = _getLastVotingPowerSnapshot(
            _votingPowerSnapshotsByVoter[msg.sender]
        );
        _rebalanceDelegates(msg.sender, oldDelegate, delegate, snap, snap);
        emit VotingPowerDelegated(msg.sender, delegate, snap.intrinsicVotingPower);
    }

    // Transfer party host status to another.
    function abdicate(address newPartyHost) external onlyHost {
        require(!isHost[newPartyHost]);
        isHost[msg.sender] = false;
        isHost[newPartyHost] = true;
    }

    // Move all `token` funds into a distribution contract to be proportionally
    // claimed by members with voting power at the current block number.
    function distribute(IERC20 token)
        external
        onlyActiveMember
        returns (uint256 distributionId)
    {
        TokenDistributor distributor = TokenDistributor(
            _GLOBALS.getAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR)
        );
        uint256 value = 0;
        if (token != IERC20(0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee)) {
            token.compatTransfer(address(distributor), token.balanceOf(address(this)));
        } else {
            value = address(this).balance;
        }
        distributionId = distributor.createDistribution{ value: value }(token);
        emit DistributionCreated(distributionId, token);
    }

    // Will also cast sender's votes for proposal.
    function propose(Proposal calldata proposal)
        external
        returns (uint256 proposalId)
    {
        uint256 proposalId = ++lastProposalId;
        (
            _proposalInfoByProposalId[proposalId].values,
            _proposalInfoByProposalId[proposalId].hash
        ) = (
            ProposalInfoValues({
                proposedTime: uint40(block.timestamp),
                passedTime: 0,
                executedTime: 0,
                completedTime: 0,
                votes: 0
            }),
            _getProposalHash(proposal),
        );
        emit Proposed(proposalId, msg.sender, proposal);
        if (accept(proposalId) == 0) {
            revert ProposalHasNoVotesError(proposalId);
        }
    }

    function accept(uint256 proposalId)
        public
        returns (uint256 totalVotes)
    {
        ProposalInfo storage info = _proposalInfoByProposalId[proposalId];
        ProposalInfoValues memory values = info.values;

        {
            ProposalState state = _getProposalState(values);
            if (
                state != ProposalState.Voting &&
                state != ProposalState.Passed &&
                state != ProposalState.Ready
            ) {
                revert BadProposalStateError(state);
            }
        }

        // Cannot vote twice.
        require(!info.hasVoted[msg.sender], 'ALREADY_VOTED');
        info.hasVoted[msg.sender] = true;

        uint96 votingPower =
            getVotingPowerAt(msg.sender, values.proposedTime);
        values.votes += votingPower;
        info.values = values;
        emit ProposalAccepted(proposalId, msg.sender, votingPower);

        if (values.passedTime == 0 && _areVotesPassing(
            values.votes,
            governanceValues.totalVotingPower,
            governanceValues.passThresholdBps))
        {
            info.values.passedTime = uint40(block.timestamp);
            emit ProposalPassed(proposalId);
        }
        return values.votes;
    }

    function veto(uint256 proposalId) external onlyHost {
        // Setting `votes` to -1 indicates a veto.
        ProposalInfo storage info = _proposalInfoByProposalId[proposalId];
        ProposalInfoValues memory values = info.values;

        {
            ProposalState state = _getProposalState(values);
            // Proposal must be in one of the following states.
            if (
                state != ProposalState.Voting &&
                state != ProposalState.Passed &&
                state != ProposalState.Ready
            ) {
                revert BadProposalStateError(state);
            }
        }

        // -1 indicates veto.
        info.values.votes = uint96(int96(-1));
        emit ProposalVetoed(proposalId, msg.sender);
    }

    // Executes a passed proposal.
    // The proposal must be in the Ready or InProgress state.
    // For multi-step/tx proposals, this should be called repeatedly.
    // `progressData` is the data emitted in the `ProposalExecutionProgress` event
    // by `IProposalExecutionEngine` for the last execute call on this proposal.
    // A proposal that has been executed but still requires further execute calls
    // will have the state of `InProgress`.
    // No other proposals may be executed if there is a an incomplete proposal.
    // When the proposal has completed (no more further execute calls necessary),
    // a `ProposalCompleted` event will be emitted.
    function execute(uint256 proposalId, Proposal calldata proposal, bytes memory progressData)
        external
        payable
    {
        ProposalInfo storage proposalInfo = _proposalInfoByProposalId[proposalId];
        {
            bytes32 actualHash = _getProposalHash(proposal);
            bytes32 proposalHash = proposalInfo.hash;
            if (proposalHash != proposalHash) {
                revert BadProposalHashError(proposalHash, actualHash);
            }
        }
        ProposalInfoValues memory infoValues = proposalInfo.values;
        ProposalState state = _getProposalState(infoValues);
        if (state != ProposalState.Ready && state != ProposalState.InProgress) {
            revert BadProposalStateError(state);
        }
        if (state == ProposalState.Ready) {
            if (proposal.maxExecutableTime < block.timestamp) {
                revert ExecutionTimeExceededError(
                    proposal.maxExecutableTime,
                    uint40(block.timestamp)
                );
            }
            proposalInfo.values.executedTime = uint40(block.timestamp);
        }
        IProposalExecutionEngine.ProposalExecutionStatus es =
            _executeProposal(
                proposalId,
                proposal,
                _getProposalFlags(infoValues)
            );
        emit ProposalExecuted(proposalId, msg.sender);
        if (es == IProposalExecutionEngine.ProposalExecutionStatus.Complete) {
            proposalInfo.values.completedTime = uint40(block.timestamp);
            emit ProposalCompleted(proposalId);
        }
    }

    function _executeProposal(
        uint256 proposalId,
        Proposal memory proposal,
        uint32 flags
    )
        private
        returns (IProposalExecutionEngine.ProposalExecutionStatus es)
    {
        IProposalExecutionEngine.ExecuteProposalParams executeParams =
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: bytes32(proposalId),
                proposalData: proposal.proposalData,
                progressData: progressData,
                preciousToken: preciousToken,
                preciousTokenId: preciousTokenId,
                flags: flags
            });
        (bool success, bytes memory revertData) =
            address(LibProposal.getProposalExecutionEngine())
                .delegatecall(abi.encodeCall(
                    IProposalExecutionEngine.executeProposal,
                    executeParams
                ));
        if (!success) {
            revertData.rawRevert();
        }
        (es) = abi.decode(
            revertData,
            (IProposalExecutionEngine.ProposalExecutionStatus)
        );
    }

    // Get the most recent voting power snapshot <= timestamp.
    function _getVotingPowerSnapshotAt(address voter, uint40 timestamp)
        private
        view
        returns (VotingPowerSnapshot memory shot)
    {
        VotingPowerSnapshot[] storage snaps = _votingPowerSnapshotsByVoter[voter];
        uint256 n = snaps.length;
        uint256 p = n / 2; // Search index.
        while (n != 0) {
            VotingPowerSnapshot memory shot_ = snaps[p];
            if (timestamp == shot_.timestamp) {
                // Entry at exact time.
                votingPower = shot_;
                break;
            }
            n /= 2;
            if (timestamp > shot_.timestamp) {
                // Entry is older. This is our best guess for now.
                votingPower = shot_;
                p += (n + 1) / 2; // Move search index to middle of lower half.
            } else /* if (timestamp < timestamp_) */ {
                // Entry is too recent.
                p -= (n + 1) / 2; // Move search index to middle of upper half.
            }
        }
    }

    function _getProposalHash(Proposal calldata proposal)
        private
        view
        returns (bytes32 h)
    {
        // Hash the proposal in-place. Equivalent to:
        // keccak256(abi.encode(
        //   proposal.minExecutableTime,
        //   proposal.nonce,
        //   keccak256(proposal.proposalData)
        // ))
        bytes32 dataHash = keccak256(proposal.proposalData);
        assembly {
            // Overwrite the data field with the hash of its contents and then
            // hash the struct.
            let dataPos := add(proposal, 0x40)
            let t := mload(dataPos)
            mstore(dataPos, dataHash)
            h := keccak256(proposal, 0x60)
            // Restore the data field.
            mstore(dataPos, t)
        }
    }


    // Transfers some voting power of `from` to `to`. The total voting power of
    // their respective delegates will be updated as well.
    function _transferVotingPower(address from, address to, uint256 power)
        internal
    {
        assert(power <= type(int192).max);
        _adjustVotingPower(from, -int192(power), address(0));
        _adjustVotingPower(to, int192(power), address(0));
    }

    // Increase `voter`'s intrinsic voting power and update their delegate if delegate is nonzero.
    function _adjustVotingPower(address voter, int192 votingPower, address delegate)
        private
    {
        VotingPowerSnapshot[] storage voterSnaps = _votingPowerSnapshotsByVoter[voter];
        VotingPowerSnapshot memory oldSnap = _getLastVotingPowerSnapshot(voterSnaps);
        uint256 oldDelegate = delegationsByVoter[voter];
        // If `delegate` is zero, use the current delegate.
        delegate = delegate == address(0) ? oldDelegate : delegate;
        // If `delegate` is still zero (`voter` never delegated), set the delegate
        // to themself.
        delegate = delgate == address(0) ? voter : delegate;
        VotingPowerSnapshot memory newSnap = VotingPowerSnapshot({
            timestamp: block.timestamp,
            delegatedVotingPower: oldSnap.delegatedVotingPower,
            intrinsicVotingPower: _safeCastToUint96(
                int192(oldSnap.intrinsicVotingPower) + votingPower
            ),
            isDelegated: delegate != voter
        });
        voerSnaps.push(newSnap);
        delegationsByVoter[voter] = delegate;
        // Handle rebalancing delegates.
        _rebalanceDelegates(voter, oldDelegate, delegate, oldSnap, newSnap);
    }

    // Update the delegated voting power of the old and new delegates delegated to
    // by `voter` based on the snapshot change.
    function _rebalanceDelegates(
        address voter,
        address oldDelegate,
        address newDelegate,
        VotingPowerSnapshot memory oldSnap,
        VotingPowerSnapshot memory newSnap
    )
        private
    {
        if (newDelegate == address(0)) {
            revert InvalidDelegateError(delegate);
        }
        {
            if (oldDelegate != address(0) && oldDelegate != newDelegate) {
                // Remove past voting power from old delegate.
                VotingPowerSnapshot[] storage oldDelegateSnaps =
                    _votingPowerSnapshotsByVoter[oldDelegate];
                VotingPowerSnapshot memory oldDelegateShot =
                    _getLastVotingPowerSnapshot(oldDelegateSnaps);
                oldDelegateSnaps.push(VotingPowerSnapshot({
                    timestamp: block.timstamp,
                    delegatedVotingPower: _safeCastToUint96(
                        int192(oldDelegateShot.delegatedVotingPower) +
                            oldSnap.intrinsicVotingPower
                    ),
                    intrinsicVotingPower: oldDelegateShot.intrinsicVotingPower,
                    isDelegated: oldDelegateShot.isDelegated
                }));
            }
        }
        if (delegate != voter) { // Not delegating to self.
            // Add new voting power to new delegate.
            VotingPowerSnapshot[] storage newDelegateSnaps =
                _votingPowerSnapshotsByVoter[delegate];
            VotingPowerSnapshot memory newDelegateShot =
                _getLastVotingPowerSnapshot(newDelegateSnaps);
            newDelegateSnaps.push(VotingPowerSnapshot({
                timstamp: block.timstamp,
                delegatedVotingPower: _safeCastToUint96(
                    int192(newDelegateShot.delegatedVotingPower) +
                        newSnap.intrinsicVotingPower
                ),
                intrinsicVotingPower: newDelegateShot.intrinsicVotingPower,
                isDelegated: newDelegateShot.isDelegated
            }));
        }
        emit VotingPowerDelegated(owner, delegate, newSnap.intrinsicVotingPower);
    }

    function _getLastVotingPowerSnapshot(VotingPowerSnapshot[] storage snaps)
        private
        view
        returns (VotingPowerSnapshot memory shot)
    {
        uint256 n = snaps.length;
        if (n != 0) {
            shot = snaps[snaps.length - 1];
        }
    }

    // TODO: accept storage vars?
    function _getProposalFlags(ProposalInfoValues memory pv)
        private
        view
        returns (uint256)
    {
        if (pv.votes >= governanceValues.totalVotingPower) {
            // Passed unanimously.
            return LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        }
        return 0;
    }

    function _getProposalState(ProposalInfoValues memory pv)
        private
        view
        returns (ProposalState state)
    {
        // Never proposed.
        if (pv.proposedTime == 0) {
            return ProposalState.Invalid;
        }
        // Executed at least once.
        if (pv.executedTime != 0) {
            return pv.completedTime == 0
                ? ProposalState.Complete
                : ProposalState.InProgress;
        }
        // Vetoed.
        if (pv.votes == uint96(int128(-1))) {
            return ProposalState.Defeated;
        }
        uint40 t = uint40(block.timestamp);
        GovernanceValues memory gv = governanceValues;
        if (pv.passedTime != 0) {
            // Ready.
            if (pv.passedTime + gv.executionDelayInSeconds <= t) {
                return ProposalState.Ready;
            }
            // Passed.
            return ProposalState.Passed;
        }
        // Voting window expired.
        if (pv.proposedTime + gv.voteDurationInSeconds <= t) {
            return ProposalState.Defeated;
        }
        return ProposalState.Voting;
    }

    function _areVotesPassing(
        uint96 voteCount,
        uint96 totalVotingPower,
        uint16 passThresholdBps
    )
        private
        pure
        returns (bool)
    {
          return uint256(voteCount) * 1e4
            / uint256(totalVotingPower) >= uint256(passThresholdBps);
    }

    function _safeCastToUint96(int192 i192) private pure returns (uint96) {
        if (i192 < 0 || i192 > type(uint96).max) {
            revert Int192ToUint96CastOutOfRange(i192);
        }
        return uint96(uint192(i192));
    }
}
