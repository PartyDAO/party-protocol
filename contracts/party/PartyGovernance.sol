// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Base contract for a Party encapsulating all governance functionality.
contract PartyGovernance is
    ITokenDistributorParty,
    ReadOnlyDelegateCall
{
    enum ProposalState {
        Invalid,
        Voting,
        Defeated,
        Passed,
        Unexecutable,
        Ready,
        InProgress,
        Complete
    }

    struct GovernanceOpts {
        // Address of initial party hosts.
        address[] hosts;
        // The contract of the NFT we're trying to protect.
        IERC721 preciousToken;
        // The id of the NFT we're trying to protect.
        uint256 preciousTokenId;
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
        // Combined intrinsic and delegated voting power for this user
        // at `blockNumber`. Does not double-count self-delegations.
        uint128 votingPower;
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
    event VotingPowerDelegated(address owner, address delegate, uint256 votingPower)

    error BadProposalStateError(ProposalState state);
    error ProposalExistsError(uint256 proposalId);
    error BadProposalHashError(bytes32 proposalHash, bytes32 actualHash);

    IGlobals private immutable _GLOBALS;

    GovernanceValues public governanceValues;
    // The contract of the NFT we're trying to protect.
    IERC721 preciousToken;
    // The id of the NFT we're trying to protect.
    uint256 preciousTokenId;
    // The last proposal ID that was used. 0 means no proposals have been made.
    uint256 lastProposalId;
    // Whether an address is a party host.
    mapping(address => bool) public isHost;
    // Snapshots of voting power per user, each sorted by increasing time.
    mapping(address => VotingPowerSnapshot[]) private _votingPowerSnapshotsByVoter;
    // ProposalInfo by proposal ID.
    mapping(uint256 => ProposalInfo) private _proposalInfoByProposalId;

    modifier onlyHost() {
        require(isHost[msg.sender], "ONLY_HOST");
        _;
    }

    constructor() {
        _GLOBALS = IPartyFactory(msg.sender)._GLOBALS();
    }

    function initialize(GovernanceOpts memory opts)
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
        preciousToken = opts.preciousToken;
        preciousTokenId = opts.preciousTokenId;
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

    // Get the voting power of a user at a timestamp.
    function getVotingPowerAt(address voter, uint40 timestamp)
        external
        view
        returns (uint128 votingPower)
    {
        VotingPowerSnapshot[] storage snaps = _votingPowerSnapshotsByVoter[voter];
        uint256 n = snaps.length;
        uint256 p = n / 2;
        while (n != 0) {
            VotingPowerSnapshot memory shot = snaps[p];
            if (timestamp == shot.timestamp) {
                // Entry at exact time.
                votingPower = shot.power;
                break;
            }
            n /= 2;
            if (timestamp > shot.timestamp) {
                // Entry is older. Can use this snapshot's power for now.
                votingPower = shot.power;
                p += (n + 1) / 2;
            } else if (timestamp < timestamp_) {
                // Entry is younger.
                p -= (n + 1) / 2;
            }
        }
    }

    function _getProposalHash(Proposal calldata proposal)
        internal
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
            let dataPos = add(proposal, 0x40)
            let t := mload(dataPos)
            mstore(dataPos, dataHash)
            h := keccak256(proposal, 0x60)
            // Restore the data field.
            mstore(dataPos, t)
        }
    }

    function getProposalState(uint256 proposalId)
        external
        view
        returns (ProposalState state)
    {
        return _getProposalState(_proposalInfoByProposalId[proposalId]);
    }

    function delegateVotingPower(address delegate) external view returns (uint256)
    {

        // ...
        emit VotingPowerDelegated(msg.sender, delegate, votingPower)
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
        ITokenDistributor distributor = ITokenDistributor(
            _GLOBALS.getAddress(LibGobals.GLOBAL_TOKEN_DISTRIBUTOR)
        );
        uint256 value = 0;
        if (token != 0xeee...) {
            _safeTransferERC20(address(distributor), token.balanceOf(address(this)));
        } else {
            value = address(this).balance;
        }
        distributionId = distributor.createDistribution{ value: value }(token);
        emit DistributionCreated(distributionId, token);
    }

    // Will also cast sender's votes for proposal.
    function propose(bytes memory proposal) external returns (uint256 proposalId) {
        uint256 proposalId = ++lastProposalId;
        _proposalInfoByProposalId[proposalId] = ProposalInfo({
            values: ProposalInfoValues({
                proposedTime: uint40(block.timestamp),
                passedTime: 0,
                executedTime: 0,
                completedTime: 0,
                votes: 0
            }),
            hash: _getProposalHash(proposal),
        });
        emit Proposed(proposalId, msg.sender, proposal);
        accept(proposalId);
    }

    function accept(uint256 proposalId)
        external
    {
        ProposalInfo storage info = _proposalInfoByProposalId[proposalId];
        ProposalInfoValues memory values = info.values;

        ProposalState state = _getProposalState(values);
        if (state != ProposalState.Voting) {
            revert BadProposalStateError(state);
        }
        // Cannot vote twice.
        require(!info.hasVoted[msg.sender], 'ALREADY_VOTED');
        info.hasVoted[msg.sender] = true;

        uint256 votingPower =
            uint96(getVotingPowerAt(msg.sender, values.proposedTime));
        values.votes += votingPower;
        emit ProposalAccepted(proposalId, msg.sender, votingPower);

        if (values.passedTime == 0 && _areVotesPassing(
            values.votes,
            governanceValues.totalVotingPower,
            gv.values.passThresholdBps))
        {
            info.values.passedTime = uint40(block.timestamp);
            emit ProposalPassed(proposalId);
        }
    }

    function veto(uint256 proposalId) external onlyHost {
        // Setting `votes` to -1 indicates a veto.
        ProposalInfo storage info = _proposalInfoByProposalId[proposalId];
        ProposalInfoValues memory values = info.values;

        ProposalState state = _getProposalState(values);
        // Proposal must be in one of the following states.
        if (
            state != ProposalState.Voting &&
            state != ProposalState.Passed &&
            state != ProposalState.Ready
        ) {
            revert BadProposalStateError(state);
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

    // Transfers some voting power of `from` to `to`. The total voting power of
    // their respective delegatees will be updated as well.
    function _transferVotingPower(address from, address to, uint256 power)
        internal
    {
        // ...
    }

    // Add to the base voting power of `owner` and delegate all votes to `delegate`
    function _mintVotingPower(address owner, uint256 votingPower, address delegate)
        internal
    {
        // Add the voting power from the last snapshot.
        VotingPowerSnapshot[] storage snaps = _votingPowerSnapshotsByVoter[owner];
        uint256 numSnaps = snaps.length;
        if (numSnaps != 0) {
            votingPower += snaps[numSnaps - 1];
        }
        snaps.push(VotingPowerSnapshot({
            timestamp: block.timestamp,
            votingPower: votingPower
        }));
        // TODO: delegates?
        emit VotingPowerDelegated(owner, delegate, votingPower)
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

    function _getProposalState(ProposalInfoValues memory values)
        private
        view
        returns (ProposalState state)
    {
        // Never proposed.
        if (values.proposedTime == 0) {
            return ProposalState.Invalid;
        }
        // Executed at least once.
        if (values.executedTime != 0) {
            return values.completedTime == 0
                ? ProposalState.Complete
                : ProposalState.InProgress;
        }
        // Vetoed.
        if (values.votes == uint96(int128(-1))) {
            return ProposalState.Defeated;
        }
        // ...
        // Passed.
        if (values.passedTime != 0) {
            return ProposalState.Passed;
        }
        uint40 t = uint40(block.timstamp);
        GovernanceValues memory gv = governanceValues;
        // Voting window expired.
        if (t >= values.proposedTime + gv.voteDurationInSeconds) {
            return ProposalState.Defeated;
        }
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

}
