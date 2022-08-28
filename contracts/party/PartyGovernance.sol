// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../distribution/ITokenDistributorParty.sol";
import "../distribution/ITokenDistributor.sol";
import "../utils/ReadOnlyDelegateCall.sol";
import "../tokens/IERC721.sol";
import "../tokens/IERC20.sol";
import "../tokens/IERC1155.sol";
import "../tokens/ERC721Receiver.sol";
import "../tokens/ERC1155Receiver.sol";
import "../utils/LibERC20Compat.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibSafeCast.sol";
import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../proposals/IProposalExecutionEngine.sol";
import "../proposals/LibProposal.sol";
import "../proposals/ProposalStorage.sol";

import "./IPartyFactory.sol";

/// @notice Base contract for a Party encapsulating all governance functionality.
abstract contract PartyGovernance is
    ITokenDistributorParty,
    ERC721Receiver,
    ERC1155Receiver,
    ProposalStorage,
    Implementation,
    ReadOnlyDelegateCall
{
    using LibERC20Compat for IERC20;
    using LibRawResult for bytes;
    using LibSafeCast for uint256;
    using LibSafeCast for int192;
    using LibSafeCast for uint96;

    // States a proposal can be in.
    enum ProposalStatus {
        // The proposal does not exist.
        Invalid,
        // The proposal has been proposed (via `propose()`), has not been vetoed
        // by a party host, and is within the voting window. Members can vote on
        // the proposal and party hosts can veto the proposal.
        Voting,
        // The proposal has either exceeded its voting window without reaching
        // `passThresholdBps` of votes or was vetoed by a party host.
        Defeated,
        // The proposal reached at least `passThresholdBps` of votes but is still
        // waiting for `executionDelay` to pass before it can be executed. Members
        // can continue to vote on the proposal and party hosts can veto at this time.
        Passed,
        // Same as `Passed` but now `executionDelay` has been satisfied. Any member
        // may execute the proposal via `execute()`, unless `maxExecutableTime`
        // has arrived.
        Ready,
        // The proposal has been executed at least once but has further steps to
        // complete so it needs to be executed again. No other proposals may be
        // executed while a proposal is in the `InProgress` state. No voting or
        // vetoing of the proposal is allowed, however it may be forcibly cancelled
        // via `cancel()` if the `cancelDelay` has passed since being first executed.
        InProgress,
        // The proposal was executed and completed all its steps. No voting or
        // vetoing can occur and it cannot be cancelled nor executed again.
        Complete,
        // The proposal was executed at least once but did not complete before
        // `cancelDelay` seconds passed since the first execute and was forcibly cancelled.
        Cancelled
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
        // Fee bps for distributions.
        uint16 feeBps;
        // Fee recipeint for distributions.
        address payable feeRecipient;
    }

    // Subset of `GovernanceOpts` that are commonly read together for
    // efficiency.
    struct GovernanceValues {
        uint40 voteDuration;
        uint40 executionDelay;
        uint16 passThresholdBps;
        uint96 totalVotingPower;
    }

    // A snapshot of voting power for a member.
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

    // Proposal details chosen by proposer.
    struct Proposal {
        // Time beyond which the proposal can no longer be executed.
        // If the proposal has already been executed, and is still InProgress,
        // this value is ignored.
        uint40 maxExecutableTime;
        // The minimum seconds this proposal can remain in the InProgress status
        // before it can be cancelled.
        uint40 cancelDelay;
        // Encoded proposal data. The first 4 bytes are the proposal type, followed
        // by encoded proposal args specific to the proposal type. See
        // ProposalExecutionEngine for details.
        bytes proposalData;
    }

    // Accounting and state tracking values for a proposal.
    // Fits in a word.
    struct ProposalStateValues {
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

    // Storage states for a proposal.
    struct ProposalState {
        // Accounting and state tracking values.
        ProposalStateValues values;
        // Hash of the proposal.
        bytes32 hash;
        // Whether a member has voted for (accepted) this proposal already.
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

    event PartyInitialized(GovernanceOpts opts, IERC721[] preciousTokens, uint256[] preciousTokenIds);
    event ProposalPassed(uint256 indexed proposalId);
    event ProposalVetoed(uint256 indexed proposalId, address host);
    event ProposalExecuted(uint256 indexed proposalId, address executor, bytes nextProgressData);
    event ProposalCancelled(uint256 indexed proposalId);
    event DistributionCreated(ITokenDistributor.TokenType tokenType, address token, uint256 tokenId);
    event VotingPowerDelegated(address indexed owner, address indexed delegate);
    event HostStatusTransferred(address oldHost, address newHost);

    error BadProposalStatusError(ProposalStatus status);
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
    error ProposalCannotBeCancelledYetError(uint40 currentTime, uint40 cancelTime);
    error InvalidBpsError(uint16 bps);

    uint256 constant private UINT40_HIGH_BIT = 1 << 39;
    uint96 constant private VETO_VALUE = uint96(int96(-1));

    IGlobals private immutable _GLOBALS;

    /// @notice Whether the DAO has emergency powers for this party.
    bool public emergencyExecuteDisabled;
    /// @notice Distribution fee bps.
    uint16 public feeBps;
    /// @notice Distribution fee recipient.
    address payable public feeRecipient;
    /// @notice The last proposal ID that was used. 0 means no proposals have been made.
    uint256 public lastProposalId;
    /// @notice Whether an address is a party host.
    mapping(address => bool) public isHost;
    /// @notice The last person a voter delegated its voting power to.
    mapping(address => address) public delegationsByVoter;
    // Constant governance parameters, fixed from the inception of this party.
    GovernanceValues private _governanceValues;
    // ProposalState by proposal ID.
    mapping(uint256 => ProposalState) private _proposalStateByProposalId;
    // Snapshots of voting power per user, each sorted by increasing time.
    mapping(address => VotingPowerSnapshot[]) private _votingPowerSnapshotsByVoter;

    modifier onlyHost() {
        if (!isHost[msg.sender]) {
            revert OnlyPartyHostError();
        }
        _;
    }

    // Caller must own a governance NFT at the current time.
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

    // Only the party dao multisig can call.
    modifier onlyPartyDao() {
        {
            address partyDao = _GLOBALS.getAddress(LibGlobals.GLOBAL_DAO_WALLET);
            if (msg.sender != partyDao) {
                revert OnlyPartyDaoError(msg.sender, partyDao);
            }
        }
        _;
    }

    // Only the party dao multisig or a party host can call.
    modifier onlyPartyDaoOrHost() {
        address partyDao = _GLOBALS.getAddress(LibGlobals.GLOBAL_DAO_WALLET);
        if (msg.sender != partyDao && !isHost[msg.sender]) {
            revert OnlyPartyDaoOrHostError(msg.sender, partyDao);
        }
        _;
    }

    // Only if emergencyExecuteDisabled is not true.
    modifier onlyWhenEmergencyExecuteAllowed() {
        if (emergencyExecuteDisabled) {
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
        if (opts.feeBps > 1e4) {
            revert InvalidBpsError(opts.feeBps);
        }
        if (opts.passThresholdBps > 1e4) {
            revert InvalidBpsError(opts.passThresholdBps);
        }
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
        feeBps = opts.feeBps;
        feeRecipient = opts.feeRecipient;
        _setPreciousList(preciousTokens, preciousTokenIds);
        for (uint256 i=0; i < opts.hosts.length; ++i) {
            isHost[opts.hosts[i]] = true;
        }
        emit PartyInitialized(opts, preciousTokens, preciousTokenIds);
    }

    /// @dev Forward all unknown read-only calls to the proposal execution engine.
    ///      Initial use case is to facilitate eip-1271 signatures.
    fallback() external {
        _readOnlyDelegateCall(
            address(_getProposalExecutionEngine()),
            msg.data
        );
    }

    /// @notice Combined logic for ERC721Receiver and ERC1155Receiver
    function supportsInterface(bytes4 interfaceId)
        public
        override(ERC721Receiver, ERC1155Receiver)
        virtual
        pure
        returns (bool)
    {
        return ERC721Receiver.supportsInterface(interfaceId) ||
            ERC1155Receiver.supportsInterface(interfaceId);
    }

    /// @notice Get the current IProposalExecutionEngine instance.
    function getProposalExecutionEngine()
        external
        view
        returns (IProposalExecutionEngine)
    {
        return _getProposalExecutionEngine();
    }

    /// @notice Get the hash of the list of precious NFTs guarded by the party.
    function getPreciousListHash() external view returns (bytes32) {
        return _getPreciousListHash();
    }

    /// @notice Get the total voting power of `voter` at a `timestamp`.
    function getVotingPowerAt(address voter, uint40 timestamp)
        external
        view
        returns (uint96 votingPower)
    {
        return getVotingPowerAt(voter, timestamp, type(uint256).max);
    }

    /// @notice Get the total voting power of `voter` at a snapshot `snapIndex`, with checks to
    ///         make sure it is the latest voting snapshot =< `timestamp`.
    function getVotingPowerAt(address voter, uint40 timestamp, uint256 snapIndex)
        public
        view
        returns (uint96 votingPower)
    {
        VotingPowerSnapshot memory snap = _getVotingPowerSnapshotAt(voter, timestamp, snapIndex);
        return (snap.isDelegated ? 0 : snap.intrinsicVotingPower) + snap.delegatedVotingPower;
    }

    function getProposalStateInfo(uint256 proposalId)
        external
        view
        returns (ProposalStatus status, ProposalStateValues memory values)
    {
        values = _proposalStateByProposalId[proposalId].values;
        status = _getProposalStatus(values);
    }

    /// @notice Retrieve fixed governance parameters.
    function getGovernanceValues() external view returns (GovernanceValues memory gv) {
        return _governanceValues;
    }

    /// @notice Get the hash of a proposal.
    /// @dev Proposal details are not stored on-chain so the hash is used to enforce
    ///      consistency between calls.
    function getProposalHash(Proposal memory proposal)
        public
        pure
        returns (bytes32 h)
    {
        // Hash the proposal in-place. Equivalent to:
        // keccak256(abi.encode(
        //   proposal.minExecutableTime,
        //   proposal.cancelDelay,
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

    // Get the index of the most recent voting power snapshot <= `timestamp`.
    function findVotingPowerSnapshotIndex(address voter, uint40 timestamp)
        public
        view
        returns (uint256 index)
    {
        VotingPowerSnapshot[] storage snaps = _votingPowerSnapshotsByVoter[voter];

        // Derived from Open Zeppelin binary search
        // ref: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Checkpoints.sol#L39
        uint256 high = snaps.length;
        uint256 low = 0;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (snaps[mid].timestamp > timestamp) {
                // Entry is too recent.
                high = mid;
            } else {
                // Entry is older. This is our best guess for now.
                low = mid + 1;
            }
        }

        // Return `type(uint256).max` if no valid voting snapshots found.
        return high == 0 ? type(uint256).max : high - 1;
    }

    /// @notice Pledge your intrinsic voting power to a new delegate, removing it from
    ///         the old one (if any).
    function delegateVotingPower(address delegate) external onlyDelegateCall {
        _adjustVotingPower(msg.sender, 0, delegate);
        emit VotingPowerDelegated(msg.sender, delegate);
    }

    /// @notice Transfer party host status to another.
    function abdicate(address newPartyHost) external onlyHost onlyDelegateCall {
        // 0 is a special case burn address.
        if (newPartyHost != address(0)) {
            // cannot transfer host status to an existing host.
            if(isHost[newPartyHost]) {
                revert InvalidNewHostError();
            }
            isHost[newPartyHost] = true;
        }
        isHost[msg.sender] = false;
        emit HostStatusTransferred(msg.sender, newPartyHost);
    }

    /// @notice Create a token distribution by moving the party's entire balance to
    ///         the TokenDistributor contract and immediately creating a distribution
    ///         governed by this party.
    /// @dev The feeBps and feeRecipient this party was
    ///      created with will be propagated to the distribution. Party members are
    ///      entitled to a share of the distribution's tokens proportionate to
    ///      their relative voting power in this party (less the fee).
    function distribute(
        ITokenDistributor.TokenType tokenType,
        address token,
        uint256 tokenId
    )
        external
        onlyActiveMember
        onlyDelegateCall
        returns (ITokenDistributor.DistributionInfo memory distInfo)
    {
        ITokenDistributor distributor = ITokenDistributor(
            _GLOBALS.getAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR)
        );
        emit DistributionCreated(tokenType, token, tokenId);
        if (tokenType == ITokenDistributor.TokenType.Native) {
            return distributor.createNativeDistribution
                { value: address(this).balance }(this, feeRecipient, feeBps);
        }
        assert(tokenType == ITokenDistributor.TokenType.Erc20);
        IERC20(token).compatTransfer(
            address(distributor),
            IERC20(token).balanceOf(address(this))
        );
        return distributor.createErc20Distribution(
            IERC20(token),
            this,
            feeRecipient,
            feeBps
        );
    }

    /// @notice Make a proposal for members to vote on and cast a vote to accept it
    ///         as well.
    /// @dev Only an active member (owns a governance token) can call this.
    ///      Afterwards, members can vote to support it with accept() or a party
    ///      host can unilaterally reject the proposal with veto().
    function propose(Proposal memory proposal, uint256 latestSnapIndex)
        external
        onlyActiveMember
        onlyDelegateCall
        returns (uint256 proposalId)
    {
        proposalId = ++lastProposalId;
        (
            _proposalStateByProposalId[proposalId].values,
            _proposalStateByProposalId[proposalId].hash
        ) = (
            ProposalStateValues({
                proposedTime: uint40(block.timestamp),
                passedTime: 0,
                executedTime: 0,
                completedTime: 0,
                votes: 0
            }),
            getProposalHash(proposal)
        );
        emit Proposed(proposalId, msg.sender, proposal);
        accept(proposalId, latestSnapIndex);
    }

    /// @notice Vote to support a proposed proposal.
    /// @dev The voting power cast will be the effective voting power of the caller
    ///      at the time propose() was called (see getVotingPowerAt()).
    ///      If the proposal reaches passThresholdBps acceptance ratio then the
    ///      proposal will be in the Passed state and will be executable after
    ///      the executionDelay has passed, putting it in the Ready state.
    function accept(uint256 proposalId, uint256 snapIndex)
        public
        onlyDelegateCall
        returns (uint256 totalVotes)
    {
        ProposalState storage info = _proposalStateByProposalId[proposalId];
        ProposalStateValues memory values = info.values;

        // Can only vote in certain proposal statuses.
        {
            ProposalStatus status = _getProposalStatus(values);
            // Allow voting even if the proposal is passed/ready so it can
            // potentially reach 100% consensus, which unlocks special
            // behaviors for certain proposal types.
            if (
                status != ProposalStatus.Voting &&
                status != ProposalStatus.Passed &&
                status != ProposalStatus.Ready
            ) {
                revert BadProposalStatusError(status);
            }
        }

        // Cannot vote twice.
        if (info.hasVoted[msg.sender]) {
            revert AlreadyVotedError(msg.sender);
        }
        info.hasVoted[msg.sender] = true;

        uint96 votingPower = getVotingPowerAt(msg.sender, values.proposedTime, snapIndex);
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

    /// @notice As a party host, veto a proposal, unilaterally rejecting it.
    /// @dev The proposal will never be executable and cannot be voted on anymore.
    ///      A proposal that has been already executed at least once (in the InProgress status)
    ///      cannot be vetoed.
    function veto(uint256 proposalId) external onlyHost onlyDelegateCall {
        // Setting `votes` to -1 indicates a veto.
        ProposalState storage info = _proposalStateByProposalId[proposalId];
        ProposalStateValues memory values = info.values;

        {
            ProposalStatus status = _getProposalStatus(values);
            // Proposal must be in one of the following states.
            if (
                status != ProposalStatus.Voting &&
                status != ProposalStatus.Passed &&
                status != ProposalStatus.Ready
            ) {
                revert BadProposalStatusError(status);
            }
        }

        // -1 indicates veto.
        info.values.votes = VETO_VALUE;
        emit ProposalVetoed(proposalId, msg.sender);
    }

    /// @notice Executes a proposal that has passed governance.
    /// @dev The proposal must be in the Ready or InProgress status.
    ///      A ProposalExecuted event will be emitted with a non-empty nextProgressData
    ///      if the proposal has extra steps (must be executed again) to carry out,
    ///      in which case nextProgressData should be passed into the next execute() call.
    ///      The ProposalExecutionEngine enforces that only one InProgress proposal
    ///      is active at a time, so that proposal must be completed or cancelled via cancel()
    ///      in order to execute a different proposal.
    function execute(
        uint256 proposalId,
        Proposal memory proposal,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        bytes calldata progressData
    )
        external
        payable
        onlyActiveMember
        onlyDelegateCall
    {
        ProposalState storage proposalState = _proposalStateByProposalId[proposalId];
        // Proposal details must remain the same from propose().
        _validateProposalHash(proposal, proposalState.hash);
        ProposalStateValues memory values = proposalState.values;
        ProposalStatus status = _getProposalStatus(values);
        // The proposal must be executable or have already been executed but still
        // has more steps to go.
        if (status != ProposalStatus.Ready && status != ProposalStatus.InProgress) {
            revert BadProposalStatusError(status);
        }
        if (status == ProposalStatus.Ready) {
            // If the proposal has not been executed yet, make sure it hasn't
            // expired. Note that proposals that have been executed
            // (but still have more steps) ignore `maxExecutableTime`.
            if (proposal.maxExecutableTime < block.timestamp) {
                revert ExecutionTimeExceededError(
                    proposal.maxExecutableTime,
                    uint40(block.timestamp)
                );
            }
            proposalState.values.executedTime = uint40(block.timestamp);
        }
        // Check that the precious list is valid.
        if (!_isPreciousListCorrect(preciousTokens, preciousTokenIds)) {
            revert BadPreciousListError();
        }
        // Preemptively set the proposal to completed to avoid it being executed
        // again in a deeper call.
        proposalState.values.completedTime = uint40(block.timestamp);
        bool completed = _executeProposal(
            proposalId,
            proposal,
            preciousTokens,
            preciousTokenIds,
            _getProposalFlags(values),
            progressData
        );
        if (!completed) {
            // Proposal did not complete.
            proposalState.values.completedTime = 0;
        }
    }

    /// @notice Cancel a (probably stuck) InProgress proposal.
    /// @dev proposal.cancelDelay seconds must have passed since it was first
    ///       executed for this to be valid.
    ///       The currently active proposal will simply be yeeted out of existence
    ///       so another proposal can execute.
    ///       This is intended to be a last resort and can leave the party
    ///       in a broken state. Whenever possible, active proposals should be
    ///       allowed to complete their lifecycle.
    function cancel(uint256 proposalId, Proposal calldata proposal)
        external
        onlyActiveMember
        onlyDelegateCall
    {
        ProposalState storage proposalState = _proposalStateByProposalId[proposalId];
        // Proposal details must remain the same from propose().
        _validateProposalHash(proposal, proposalState.hash);
        ProposalStateValues memory values = proposalState.values;
        {
            // Must be InProgress.
            ProposalStatus status = _getProposalStatus(values);
            if (status != ProposalStatus.InProgress) {
                revert BadProposalStatusError(status);
            }
        }
        {
            // Limit the maximum cancelDelay to the global max cancel delay
            // to mitigate parties accidentally getting stuck forever by setting an
            // unrealistic cancelDelay.
            uint256 cancelDelay = proposal.cancelDelay;
            uint256 globalMaxCancelDelay =
                _GLOBALS.getUint256(LibGlobals.GLOBAL_PROPOSAL_MAX_CANCEL_DURATION);
            if (globalMaxCancelDelay != 0) { // Only if we have one set.
                if (cancelDelay > globalMaxCancelDelay) {
                    cancelDelay = globalMaxCancelDelay;
                }
            }
            uint256 cancelTime = values.executedTime + cancelDelay;
            // Must not be too early.
            if (block.timestamp < cancelTime) {
                revert ProposalCannotBeCancelledYetError(
                    uint40(block.timestamp),
                    uint40(cancelTime)
                );
            }
        }
        // Mark the proposal as cancelled by setting the completed time to the current
        // time with the high bit set.
        proposalState.values.completedTime = uint40(block.timestamp | UINT40_HIGH_BIT);
        {
            // Delegatecall into the proposal engine impl to perform the cancel.
            (bool success, bytes memory resultData) =
            (address(_getProposalExecutionEngine())).delegatecall(abi.encodeCall(
                IProposalExecutionEngine.cancelProposal,
                (proposalId)
            ));
            if (!success) {
                resultData.rawRevert();
            }
        }
        emit ProposalCancelled(proposalId);
    }

    /// @notice As the DAO, execute an arbitrary function call from this contract.
    /// @dev Emergency actions must not be revoked for this to work.
    function emergencyExecute(
        address targetAddress,
        bytes calldata targetCallData,
        uint256 amountEth
    )
        external
        payable
        onlyPartyDao
        onlyWhenEmergencyExecuteAllowed
        onlyDelegateCall
        returns (bool)
    {
        (bool success, ) = targetAddress.call{value: amountEth}(targetCallData);
        return success;
    }

    /// @notice Revoke the DAO's ability to call emergencyExecute().
    /// @dev Either the DAO or the party host can call this.
    function disableEmergencyExecute() external onlyPartyDaoOrHost onlyDelegateCall {
        emergencyExecuteDisabled = true;
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
        returns (bool completed)
    {
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams =
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: proposalId,
                proposalData: proposal.proposalData,
                progressData: progressData,
                preciousTokens: preciousTokens,
                preciousTokenIds: preciousTokenIds,
                flags: flags
            });
        bytes memory nextProgressData;
        {
            (bool success, bytes memory resultData) =
                address(_getProposalExecutionEngine()).delegatecall(abi.encodeCall(
                    IProposalExecutionEngine.executeProposal,
                    (executeParams)
                ));
            if (!success) {
                resultData.rawRevert();
            }
            nextProgressData = abi.decode(resultData, (bytes));
        }
        emit ProposalExecuted(proposalId, msg.sender, nextProgressData);
        // If the returned progress data is empty, then the proposal completed
        // and it should not be executed again.
        return nextProgressData.length == 0;
    }

    // Get the most recent voting power snapshot <= timestamp using `hintindex` as a "hint".
    function _getVotingPowerSnapshotAt(address voter, uint40 timestamp, uint256 hintIndex)
        internal
        view
        returns (VotingPowerSnapshot memory snap)
    {
        VotingPowerSnapshot[] storage snaps = _votingPowerSnapshotsByVoter[voter];
        uint256 snapsLength = snaps.length;
        if (snapsLength != 0) {
            if (
                // Hint is within bounds.
                hintIndex < snapsLength &&
                // Snapshot is not too recent.
                snaps[hintIndex].timestamp <= timestamp &&
                // Snapshot is not too old.
                (hintIndex == snapsLength - 1 || snaps[hintIndex+1].timestamp > timestamp)
            ) {
                return snaps[hintIndex];
            }

            // Hint was wrong, fallback to binary search to find snapshot.
            hintIndex = findVotingPowerSnapshotIndex(voter, timestamp);
            // Check that snapshot was found.
            if (hintIndex != type(uint256).max) {
                return snaps[hintIndex];
            }
        }

        // No snapshot found.
        return snap;
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

    // Append a new voting power snapshot, overwriting the last one if possible.
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

    function _getProposalFlags(ProposalStateValues memory pv)
        private
        view
        returns (uint256)
    {
        if (_isUnanimousVotes(pv.votes, _governanceValues.totalVotingPower)) {
            return LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        }
        return 0;
    }

    function _getProposalStatus(ProposalStateValues memory pv)
        private
        view
        returns (ProposalStatus status)
    {
        // Never proposed.
        if (pv.proposedTime == 0) {
            return ProposalStatus.Invalid;
        }
        // Executed at least once.
        if (pv.executedTime != 0) {
            if (pv.completedTime == 0) {
                return ProposalStatus.InProgress;
            }
            // completedTime high bit will be set if cancelled.
            if (pv.completedTime & UINT40_HIGH_BIT == UINT40_HIGH_BIT) {
                return ProposalStatus.Cancelled;
            }
            return ProposalStatus.Complete;
        }
        // Vetoed.
        if (pv.votes == uint96(int96(-1))) {
            return ProposalStatus.Defeated;
        }
        uint40 t = uint40(block.timestamp);
        GovernanceValues memory gv = _governanceValues;
        if (pv.passedTime != 0) {
            // Ready.
            if (pv.passedTime + gv.executionDelay <= t) {
                return ProposalStatus.Ready;
            }
            // If unanimous, we skip the execution delay.
            if (_isUnanimousVotes(pv.votes, gv.totalVotingPower)) {
                return ProposalStatus.Ready;
            }
            // Passed.
            return ProposalStatus.Passed;
        }
        // Voting window expired.
        if (pv.proposedTime + gv.voteDuration <= t) {
            return ProposalStatus.Defeated;
        }
        return ProposalStatus.Voting;
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

    // Assert that the hash of a proposal matches expectedHash.
    function _validateProposalHash(Proposal memory proposal, bytes32 expectedHash)
        private
        pure
    {
        bytes32 actualHash = getProposalHash(proposal);
        if (expectedHash != actualHash) {
            revert BadProposalHashError(actualHash, expectedHash);
        }
    }

}
