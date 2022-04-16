// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Base contract for a Party encapsulating all governance functionality.
contract PartyGovernance {
    enum ProposalState {
        Invalid,
        Voting,
        Passed,
        Defeated,
        Expired,
        NotExecutable,
        Pending,
        Executed
    }

    struct GovernanceOpts {
        address[] chaperones;
        uint40 voteDurationInBlocks;
        uint40 executionDelayInBlocks;
        uint16 passThresholdBps;
        uint16 vetoThresholdBps;
        address erc721Token;
        uint256 erc721TokenId;
    }

    struct VotingPowerSnapshot {
        uint40 blockNumber;
        // Who the user has delegated its intrinsicVotingPower to.
        address delegate;
        // Voting power from OTHER users that have delegated to this user.
        // Any self-delegated voting power is not reflected in this value.
        uint128 delegatedVotingPower;
        // Voting power that is actually owned by this user, which is delegated.
        // to `delegate`.
        uint128 intrinsicVotingPower;
    }

    struct Proposal {
        address proposer;
        uint40 minExecutableBlockNumber;
        uint40 maxExecutableBlockNumber;
        uint256 nonce;
        bytes proposalData;
    }

    struct ProposalInfo {
        uint40 proposedBlockNumber;
        uint40 passedBlockNumer;
        uint40 vetoedBlockNumber;
        uint40 executedBlockNumber;
        bool chaperoneVetoed;
        uint128 acceptVotes;
        uint128 vetoVotes;
        mapping (address => bool) hasVoted;
    }

    event Proposed(
        bytes32 proposalId,
        address proposer,
        uint40 minExecutableBlockNumber,
        uint40 maxExecutableBlockNumber,
        bytes proposalData
    );
    event ProposalAccepted(
        bytes32 proposalId,
        address voter,
        uint256 weight
    );
    event ProposalVetoed(
        bytes32 proposalId,
        address voter,
        uint256 weight,
        bool wasDelegated
    );
    event ProposalPassed(bytes32 proposalId);
    event ProposalDefeated(bytes32 proposalId);
    event ProposalExecuted(bytes32 proposalId, address executor);
    event DistributionCreated(uint256 distributionId, IERC20 token);

    IGlobals public immutable GLOBALS;

    IPartyProposals public proposalsImpl; // Upgradable.
    uint128 public totalVotingSupply;
    GovernanceOpts public governanceOpts;
    mapping (uint256 => uint128) public votingPowerByTokenId;
    mapping (address => VotingPowerSnapshot[]) public votingPowerSnapshotsByOwner;
    mappping (bytes32 => ProposalInfo) public proposalInfoByProposalId;
    mapping (address => bool) public isChaperone;

    constructor() {
        GLOBALS = IPartyFactory(msg.sender).GLOBALS();
    }

    function getVotingPowerAt(address voter, uint256 blockNumber) external view returns (uint256);
    function getDelegatedVotingPowerAt(address voter, uint256 blockNumber) external view returns (uint256);
    function getTotalVotingPowerAt(address voter, uint256 blockNumber) external view returns (uint256);
    function getProposalId(Proposal calldata proposal) external view returns (bytes32 proposalId);
    function getProposalState(Proposal calldata proposal) external view returns (ProposalState state);
    function delegateVotingPower(address delegate) external view returns (uint256);
    function abdicate() external onlyChaperone {
        isChaperone[msg.sender] = false;
    }
    // Move all `token` funds into a distribution contract to be proportionally
    // claimed by members with voting power at the current block number.
    function distribute(IERC20 token)
        external
        onlyActiveMember
        returns (uint256 distributionId)
    {
        ITokenDistributor distributor = ITokenDistributor(GLOBALS.getAddress(TOKEN_DISTRIBUTOR));
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
    function propose(bytes memory proposal) external returns (bytes32 proposalId) {
        require(
            proposalsImpl.isValidProposal(
                governanceOpts.erc721Token,
                governanceOpts.erc721TokenId,
                proposal
            )
        );
        // ...
    }
    function accept(bytes32 proposalId) external hasNotVoted(proposalId);
    function veto(bytes32 proposalId) external hasNotVoted(proposalId);
    function chaperoneVeto(bytes32 proposalId) onlyChaperone external;
    function execute(Proposal calldata proposal)
        external
        payable
        onlyProposer(proposal) // Prevent gas grief
    {
        bytes32 proposalId = _getProposalId(proposal);
        ProposalInfo storage proposalInfo = proposalsById[proposalId];
        require(_isExecutableProposal(proposal, proposalInfo));
        proposalInfo.executedBlockNumber = block.number;
        address(proposalsImpl).delegatecall(abi.encodeCall(
            IPartyProposals.execute,
            governanceOpts.erc721Token,
            governanceOpts.erc721TokenId,
            proposal
        ));
        emit ProposalExecuted(proposalId, msg.sender);
    }
    function tryProposal(bytes calldata proposal, address handler)
        external
        payable
        returns (uint256 gasUsed, bytes memory results)
    {
        uint256 gasUsed = gasleft();
        try this._tryAndRevertProposal(proposal, msg.value, handler) {
            revert('EXPECTED REVERT');
        } catch (bytes memory err) {
            gasUsed -= gasleft();
            bool success;
            if (results.length >= 4) {
                bytes4 selector;
                assembly {
                    selector := shr(224, mload(add(err, 32)))
                }
                if (selector == HANDLER_PREFIX_SELECTOR) {
                    results = err;
                    // Trim the handler prefix
                    assembly {
                        mstore(add(results, 4), mload(results))
                        results := add(results, 4)
                    }
                    return (gasUsed, results);
                }
            }
            assembly {
                revert(add(err), mload(err))
            }
        }
    }
    function _tryAndRevertProposal(
        bytes calldata proposal,
        uint256 value,
        IProposalHandler handler
    )
        external
    {
        require(msg.sender == address(this));
        (bool s, bytes memory r) = address(proposalsImpl)
            .delegatecall{ value: value }(abi.encodeCall(IPartyProposals.execute, proposal));
        if (s) {
            r = address(handler) == address(0) ? "" : handler.handleProposalResults(proposal, r);
            uint256 rLen = r.length;
            assembly {
                // prefix with success selector
                r := add(r, 28)
                mstore(sub(r, 28), HANDLER_PREFIX_SELECTOR)
                revert(r, add(rLen, 4))
            }
        }
        assembly { revert(add(r, 32), mload(r)) }
    }
    // Transfers the entire voting power of `from` to `to`. The total voting power of
    // their respective delegatees will be updated as well.
    function _transferVotingPower(address from, address to) internal returns (uint256 votingPowerMoved);
    // Add to the base voting power of `owner` and delegate all votes to `delegate`
    function _mintVotingPower(address owner, uint256 votingPower, address delegate) internal;
    function _delegateVotingPower(address owner, address delegate) internal (uint256 votingPowerDelegated);

    function _initialize(GovernanceOpts memory opts, uint128 totalVotingSupply_) internal {
        proposalsImpl = GLOBALS.getAddress(PARTY_PROPOSALS_IMPL);
        governanceOpts = opts;
        totalVotingSupply = totalVotingSupply_;
    }
}