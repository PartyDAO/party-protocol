// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../distribution/ITokenDistributorParty.sol";
import "../distribution/TokenDistributor.sol";
import "../utils/ReadOnlyDelegateCall.sol";
import "../tokens/IERC721.sol";
import "../tokens/IERC20.sol";
import "../tokens/ERC721Receiver.sol";
import "../utils/LibERC20Compat.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibSafeCast.sol";
import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../proposals/IProposalExecutionEngine.sol";
import "../proposals/LibProposal.sol";
import "../proposals/ProposalStorage.sol";

import "./IPartyFactory.sol";

// Base contract for a Party encapsulating all governance functionality.
abstract contract PartyGovernance is
    ITokenDistributorParty,
    ERC721Receiver,
    ProposalStorage,
    ReadOnlyDelegateCall
{
    using LibERC20Compat for IERC20;
    using LibRawResult for bytes;
    using LibSafeCast for uint256;
    using LibSafeCast for int192;
    using LibSafeCast for uint96;

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
        uint40 voteDuration;
        // How long to wait after a proposal passes before it can be
        // executed.
        uint40 executionDelay;
        // Minimum ratio of accept votes to consider a proposal passed,
        // in bps, where 10,000 == 100%.
        uint16 passThresholdBps;
        // Total voting power of governance NFTs.
        uint96 totalVotingPower;
    }

    // Subset of `GovernanceOpts` that are commonly needed together for
    // efficiency.
    struct GovernanceValues {
        uint40 voteDuration;
        uint40 executionDelay;
        uint16 passThresholdBps;
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
    event VotingPowerDelegated(address owner, address delegate);
    event PreciousListSet(IERC721[] tokens, uint256[] tokenIds);
    event HostStatusTransferred(address oldHost, address newHost);

    error BadProposalStateError(ProposalState state);
    error ProposalExistsError(uint256 proposalId);
    error BadProposalHashError(bytes32 proposalHash, bytes32 actualHash);
    error ProposalHasNoVotesError(uint256 proposalId);
    error ExecutionTimeExceededError(uint40 maxExecutableTime, uint40 timestamp);
    error OnlyPartyHostError();
    error OnlyActiveMemberError();
    error InvalidDelegateError();
    error BadPreciousListError();
    error OnlyPartyDaoError(address notDao, address partyDao);
    error OnlyPartyDaoOrHostError(address notDao, address partyDao);
    error OnlyWhenEmergencyActionsAllowedError();
    error AlreadyVotedError(address voter);
    error InvalidNewHostError();

    IGlobals private immutable _GLOBALS;

    // The hash of the list of precious NFTs guarded by the party.
    bytes32 public preciousListHash;
    // The last proposal ID that was used. 0 means no proposals have been made.
    uint256 public lastProposalId;
    // Whether an address is a party host.
    mapping(address => bool) public isHost;
    // The last person a voter delegated its voting power to.
    mapping(address => address) public delegationsByVoter;
    // Constant governance parameters, fixed from the inception of this party.
    GovernanceValues private _governanceValues;
    // ProposalInfo by proposal ID.
    mapping(uint256 => ProposalInfo) private _proposalInfoByProposalId;
    // Snapshots of voting power per user, each sorted by increasing time.
    mapping(address => VotingPowerSnapshot[]) private _votingPowerSnapshotsByVoter;
    // Allows disabling of emergency withdrawals
    bool public emergencyWithdrawalsDisabled;

    modifier onlyHost() {
        if (!isHost[msg.sender]) {
            revert OnlyPartyHostError();
        }
        _;
    }

    modifier onlyActiveMember() {
        {
            VotingPowerSnapshot memory snap =
                _getLastVotingPowerSnapshotForVoter(msg.sender);
            // Must have either delegated voting power or intrinsic voting power.
            if (snap.intrinsicVotingPower == 0 && snap.delegatedVotingPower == 0) {
                revert OnlyActiveMemberError();
            }
        }
        _;
    }

    modifier onlyPartyDao() {
        {
            address partyDao = _GLOBALS.getAddress(LibGlobals.GLOBAL_DAO_WALLET);
            if (msg.sender != partyDao) {
                revert OnlyPartyDaoError(msg.sender, partyDao);
            }
        }
        _;
    }

    modifier onlyPartyDaoOrHost() {
        address partyDao = _GLOBALS.getAddress(LibGlobals.GLOBAL_DAO_WALLET);
        if (msg.sender != partyDao && !isHost[msg.sender]) {
            revert OnlyPartyDaoOrHostError(msg.sender, partyDao);
        }
        _;
    }

    modifier onlyWhenEmergencyActionsAllowed() {
        if (emergencyWithdrawalsDisabled) {
            revert OnlyWhenEmergencyActionsAllowedError();
        }
        _;
    }

    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    function _initialize(
        GovernanceOpts memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        internal
        virtual
    {
        _initProposalImpl(
            IProposalExecutionEngine(
                _GLOBALS.getAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL)
            ),
            ""
        );
        _governanceValues = GovernanceValues({
            voteDuration: opts.voteDuration,
            executionDelay: opts.executionDelay,
            passThresholdBps: opts.passThresholdBps,
            totalVotingPower: opts.totalVotingPower
        });
        _setPreciousList(preciousTokens, preciousTokenIds);
        for (uint256 i=0; i < opts.hosts.length; ++i) {
            isHost[opts.hosts[i]] = true;
        }
    }

    fallback() external {
        // Forward all unknown read-only calls to the proposal execution engine.
        // Initial use case is to facilitate eip-1271 signatures.
        _readOnlyDelegateCall(
            address(_getProposalExecutionEngine()),
            msg.data
        );
    }

    // Get the current IProposalExecutionEngine instance.
    function getProposalExecutionEngine()
        external
        view
        returns (IProposalExecutionEngine)
    {
        return _getProposalExecutionEngine();
    }

    // Get the total voting power of `voter` by a timestamp.
    function getVotingPowerAt(address voter, uint40 timestamp)
        public
        view
        returns (uint96 votingPower)
    {
        VotingPowerSnapshot memory snap = _getVotingPowerSnapshotAt(voter, timestamp);
        return (snap.isDelegated ? 0 : snap.intrinsicVotingPower) + snap.delegatedVotingPower;
    }

    function getProposalStates(uint256 proposalId)
        external
        view
        returns (ProposalState state, ProposalInfoValues memory values)
    {
        values = _proposalInfoByProposalId[proposalId].values;
        state = _getProposalState(values);
    }

    function getProposalHash(Proposal memory proposal)
        public
        pure
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

    // Pledge your intrinsic voting power to a new delegate, removing it from
    // the old one (if any).
    function delegateVotingPower(address delegate) external
    {
        _adjustVotingPower(msg.sender, 0, delegate);
        emit VotingPowerDelegated(msg.sender, delegate);
    }

    // Transfer party host status to another.
    function abdicate(address newPartyHost) external onlyHost {
        // cannot transfer host status to an existing host
        if(isHost[newPartyHost]) {
            revert InvalidNewHostError();
        }
        isHost[msg.sender] = false;
        isHost[newPartyHost] = true;
        emit HostStatusTransferred(msg.sender, newPartyHost);
    }

    // Move all `token` funds into a distribution contract to be proportionally
    // claimed by members with voting power at the current block number.
    function distribute(IERC20 token)
        external
        onlyActiveMember
        returns (TokenDistributor.DistributionInfo memory distInfo)
    {
        TokenDistributor distributor = TokenDistributor(
            payable(_GLOBALS.getAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR))
        );
        uint256 value = 0;
        if (token != IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
            token.compatTransfer(address(distributor), token.balanceOf(address(this)));
        } else {
            value = address(this).balance;
        }
        distInfo = distributor.createDistribution{ value: value }(token);
    }

    // Will also cast sender's votes for proposal.
    function propose(Proposal calldata proposal)
        external
        onlyActiveMember
        returns (uint256 proposalId)
    {
        proposalId = ++lastProposalId;
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
            getProposalHash(proposal)
        );
        emit Proposed(proposalId, msg.sender, proposal);
        accept(proposalId);
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
        if (info.hasVoted[msg.sender]) {
            revert AlreadyVotedError(msg.sender);
        }
        info.hasVoted[msg.sender] = true;

        uint96 votingPower = getVotingPowerAt(msg.sender, values.proposedTime);
        values.votes += votingPower;
        info.values = values;
        emit ProposalAccepted(proposalId, msg.sender, votingPower);

        if (values.passedTime == 0 && _areVotesPassing(
            values.votes,
            _governanceValues.totalVotingPower,
            _governanceValues.passThresholdBps))
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
    function execute(
        uint256 proposalId,
        Proposal memory proposal,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        bytes memory progressData
    )
        external
        payable
        onlyActiveMember
    {
        ProposalInfo storage proposalInfo = _proposalInfoByProposalId[proposalId];
        {
            bytes32 actualHash = getProposalHash(proposal);
            bytes32 expectedHash = proposalInfo.hash;
            if (expectedHash != actualHash) {
                revert BadProposalHashError(actualHash, expectedHash);
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
        // Check that the precious list is valid.
        if (!_isPreciousListCorrect(preciousTokens, preciousTokenIds)) {
            revert BadPreciousListError();
        }
        IProposalExecutionEngine.ProposalExecutionStatus es =
            _executeProposal(
                proposalId,
                proposal,
                preciousTokens,
                preciousTokenIds,
                _getProposalFlags(infoValues),
                progressData
            );
        emit ProposalExecuted(proposalId, msg.sender);
        if (es == IProposalExecutionEngine.ProposalExecutionStatus.Complete) {
            proposalInfo.values.completedTime = uint40(block.timestamp);
            emit ProposalCompleted(proposalId);
        }
    }

    function getGovernanceValues() public view returns (GovernanceValues memory gv) {
        return _governanceValues;
    }

    function emergencyExecute(
        address targetAddress,
        bytes calldata targetCallData,
        uint256 amountEth
    ) public onlyPartyDao onlyWhenEmergencyActionsAllowed returns (bool) {
        (bool success, ) = targetAddress.call{value: amountEth}(targetCallData);
        return success;
    }

    function disableEmergencyWithdrawals() public onlyPartyDaoOrHost {
        emergencyWithdrawalsDisabled = true;
    }

    function _executeProposal(
        uint256 proposalId,
        Proposal memory proposal,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        uint256 flags,
        bytes memory progressData
    )
        private
        returns (IProposalExecutionEngine.ProposalExecutionStatus es)
    {
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams =
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: bytes32(proposalId),
                proposalData: proposal.proposalData,
                progressData: progressData,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds,
                flags: flags
            });
        (bool success, bytes memory revertData) =
            address(_getProposalExecutionEngine())
                .delegatecall(abi.encodeWithSelector(
                    IProposalExecutionEngine.executeProposal.selector,
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
        internal
        view
        returns (VotingPowerSnapshot memory snap)
    {
        VotingPowerSnapshot[] storage snaps = _votingPowerSnapshotsByVoter[voter];

        // Open Zepplin binary search https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Checkpoints.sol#L39

        uint256 high = snaps.length;
        uint256 low = 0;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            VotingPowerSnapshot memory shot_ = snaps[mid];
            if (shot_.timestamp > timestamp) {
                // Entry is too recent.
                high = mid;
            } else {
                // Entry is older. This is our best guess for now.
                low = mid + 1;
            }
        }

        return high == 0
            ? VotingPowerSnapshot({
                timestamp: 0,
                delegatedVotingPower: 0,
                intrinsicVotingPower: 0,
                isDelegated: false
                })
            : snaps[high - 1];
    }

    // Transfers some voting power of `from` to `to`. The total voting power of
    // their respective delegates will be updated as well.
    function _transferVotingPower(address from, address to, uint256 power)
        internal
    {
        int192 powerI192 = power.safeCastUint256ToInt192();
        _adjustVotingPower(from, -powerI192, address(0));
        _adjustVotingPower(to, powerI192, address(0));
    }

    // Increase `voter`'s intrinsic voting power and update their delegate if delegate is nonzero.
    function _adjustVotingPower(address voter, int192 votingPower, address delegate)
        internal
    {
        VotingPowerSnapshot memory oldSnap =
            _getLastVotingPowerSnapshotForVoter(voter);
        address oldDelegate = delegationsByVoter[voter];
        // If `oldDelegate` is zero, `voter` never delegated, set the it to
        // themself.
        oldDelegate = oldDelegate == address(0) ? voter : oldDelegate;
        // If the new `delegate` is zero, use the current (old) delegate.
        delegate = delegate == address(0) ? oldDelegate : delegate;

        VotingPowerSnapshot memory newSnap = VotingPowerSnapshot({
            timestamp: uint40(block.timestamp),
            delegatedVotingPower: oldSnap.delegatedVotingPower,
            intrinsicVotingPower: (
                    oldSnap.intrinsicVotingPower.safeCastUint96ToInt192() + votingPower
                ).safeCastInt192ToUint96(),
            isDelegated: delegate != voter
        });
        _insertVotingPowerSnapshot(voter, newSnap);
        delegationsByVoter[voter] = delegate;
        // Handle rebalancing delegates.
        _rebalanceDelegates(voter, oldDelegate, delegate, oldSnap, newSnap);
    }

    function _getTotalVotingPower() internal view returns (uint256) {
        return _governanceValues.totalVotingPower;
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
        if (newDelegate == address(0) || oldDelegate == address(0)) {
            revert InvalidDelegateError();
        }
        if (oldDelegate != voter && oldDelegate != newDelegate) {
            // Remove past voting power from old delegate.
            VotingPowerSnapshot memory oldDelegateSnap =
                _getLastVotingPowerSnapshotForVoter(oldDelegate);
            VotingPowerSnapshot memory updatedOldDelegateSnap =
                VotingPowerSnapshot({
                    timestamp: uint40(block.timestamp),
                    delegatedVotingPower:
                        oldDelegateSnap.delegatedVotingPower -
                            oldSnap.intrinsicVotingPower,
                    intrinsicVotingPower: oldDelegateSnap.intrinsicVotingPower,
                    isDelegated: oldDelegateSnap.isDelegated
                });
            _insertVotingPowerSnapshot(oldDelegate, updatedOldDelegateSnap);
        }
        if (newDelegate != voter) { // Not delegating to self.
            // Add new voting power to new delegate.
            VotingPowerSnapshot memory newDelegateSnap =
                _getLastVotingPowerSnapshotForVoter(newDelegate);
            uint96 newDelegateDelegatedVotingPower =
                newDelegateSnap.delegatedVotingPower + newSnap.intrinsicVotingPower;
            if (newDelegate == oldDelegate) {
                // If the old and new delegate are the same, subtract the old
                // intrinsic voting power of the voter, or else we will double
                // count a portion of it.
                newDelegateDelegatedVotingPower -= oldSnap.intrinsicVotingPower;
            }
            VotingPowerSnapshot memory updatedNewDelegateSnap =
                VotingPowerSnapshot({
                    timestamp: uint40(block.timestamp),
                    delegatedVotingPower: newDelegateDelegatedVotingPower,
                    intrinsicVotingPower: newDelegateSnap.intrinsicVotingPower,
                    isDelegated: newDelegateSnap.isDelegated
                });
            _insertVotingPowerSnapshot(newDelegate, updatedNewDelegateSnap);
        }
    }

    function _insertVotingPowerSnapshot(address voter, VotingPowerSnapshot memory snap)
        private
    {
        VotingPowerSnapshot[] storage voterSnaps = _votingPowerSnapshotsByVoter[voter];
        uint256 n = voterSnaps.length;
        // If same timestamp as last entry, overwrite the last snapshot, otherwise append.
        if (n != 0) {
            VotingPowerSnapshot memory lastSnap = voterSnaps[n - 1];
            if (lastSnap.timestamp == snap.timestamp) {
                voterSnaps[n - 1] = snap;
                return;
            }
        }
        voterSnaps.push(snap);
    }

    function _getLastVotingPowerSnapshotForVoter(address voter)
        private
        view
        returns (VotingPowerSnapshot memory snap)
    {
        VotingPowerSnapshot[] storage voterSnaps = _votingPowerSnapshotsByVoter[voter];
        uint256 n = voterSnaps.length;
        if (n != 0) {
            snap = voterSnaps[n - 1];
        }
    }

    // TODO: accept storage vars?
    function _getProposalFlags(ProposalInfoValues memory pv)
        private
        view
        returns (uint256)
    {
        if (_isUnanimousVotes(pv.votes, _governanceValues.totalVotingPower)) {
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
                ? ProposalState.InProgress
                : ProposalState.Complete;
        }
        // Vetoed.
        if (pv.votes == uint96(int96(-1))) {
            return ProposalState.Defeated;
        }
        uint40 t = uint40(block.timestamp);
        GovernanceValues memory gv = _governanceValues;
        if (pv.passedTime != 0) {
            // Ready.
            if (pv.passedTime + gv.executionDelay <= t) {
                return ProposalState.Ready;
            }
            // If unanimous, we skip the execution delay.
            if (_isUnanimousVotes(pv.votes, gv.totalVotingPower)) {
                return ProposalState.Ready;
            }
            // Passed.
            return ProposalState.Passed;
        }
        // Voting window expired.
        if (pv.proposedTime + gv.voteDuration <= t) {
            return ProposalState.Defeated;
        }
        return ProposalState.Voting;
    }

    function _isUnanimousVotes(uint96 totalVotes, uint96 totalVotingPower)
        private
        pure
        returns (bool)
    {
        uint256 acceptanceRatio = (totalVotes * 1e4) / totalVotingPower;
        // If >= 99.99% acceptance, consider it unanimous.
        // The minting formula for voting power is a bit lossy, so we check
        // for slightly less than 100%.
        return acceptanceRatio >= 0.9999e4;
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

    function _setPreciousList(
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        private
    {
        assert(preciousTokens.length == preciousTokenIds.length);
        preciousListHash = _hashPreciousList(preciousTokens, preciousTokenIds);
        emit PreciousListSet(preciousTokens, preciousTokenIds);
    }

    function _isPreciousListCorrect(
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        private
        view
        returns (bool)
    {
        return preciousListHash == _hashPreciousList(preciousTokens, preciousTokenIds);
    }

    function _hashPreciousList(
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        private
        pure
        returns (bytes32)
    {
        // TODO: in asm...
        return keccak256(abi.encode(
            abi.encode(preciousTokens),
            abi.encode(preciousTokenIds)
        ));
    }
}
