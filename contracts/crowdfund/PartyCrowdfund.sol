// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../utils/LibAddress.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibSafeCast.sol";
import "../tokens/ERC721Receiver.sol";
import "../party/Party.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "./PartyCrowdfundNFT.sol";

// Base contract for PartyBid/PartyBuy.
// Holds post-win/loss logic. E.g., burning contribution NFTs and creating a
// party after winning.
abstract contract PartyCrowdfund is ERC721Receiver, PartyCrowdfundNFT {
    using LibRawResult for bytes;
    using LibSafeCast for uint256;
    using LibAddress for address payable;

    enum CrowdfundLifecycle {
        Invalid,
        Active,
        Expired,
        Busy, // Temporary. mid-settlement state
        Lost,
        Won
    }

    // PartyGovernance options that must be known and fixed at crowdfund creation.
    // This is a subset of PartyGovernance.GovernanceOpts.
    struct FixedGovernanceOpts {
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
        // Fee bps for governance distributions.
        uint16 feeBps;
        // Fee recipeint for governance distributions.
        address payable feeRecipient;
    }

    // Options to be passed into `_initialize()` when the crowdfund is created.
    struct PartyCrowdfundOptions {
        string name;
        string symbol;
        address payable splitRecipient;
        uint16 splitBps;
        address initialContributor;
        address initialDelegate;
        IGateKeeper gateKeeper;
        bytes12 gateKeeperId;
        FixedGovernanceOpts governanceOpts;
    }

    // A record of a single contribution made by a user.
    // Stored in `_contributionsByContributor`.
    struct Contribution {
        // The value of `PartyCrowdfund.totalContributions` when this contribution was made.
        uint128 previousTotalContributions;
        // How much was this contribution.
        uint128 amount;
    }

    error PartyAlreadyExistsError(Party party);
    error WrongLifecycleError(CrowdfundLifecycle lc);
    error InvalidGovernanceOptionsError(bytes32 actualHash, bytes32 expectedHash);
    error InvalidDelegateError();
    error NoPartyError();
    error OnlyContributorAllowedError();
    error NotAllowedByGateKeeperError(address contributor, IGateKeeper gateKeeper, bytes12 gateKeeperId, bytes gateData);
    error SplitRecipientAlreadyBurnedError();

    event Burned(address contributor, uint256 ethUsed, uint256 ethOwed, uint256 votingPower);
    event Contributed(address contributor, uint256 amount, address delegate, uint256 previousTotalContributions);

    IGlobals private immutable _GLOBALS;

    /// @dev The party instance created by `_createParty()`, if any.
    Party public party;
    /// @notice Who will receive a reserved portion of governance power when
    ///         the governance party is created.
    address payable public splitRecipient;
    /// @notice How much governance power to reserve for `splitRecipient`,
    ///         in bps, where 1000 = 100%.
    uint16 public splitBps;
    // Hash of party governance options passed into initialize().
    // The GovernanceOpts passed into `_createParty()` must match.
    bytes16 public governanceOptsHash;
    // The total (recorded) ETH contributed to this crowdfund.
    uint128 public totalContributions;
    // The gatekeeper contract to use (if non-null) to restrict who can
    // contribute to this crowdfund.
    IGateKeeper public gateKeeper;
    // The gatekeeper contract to use (if non-null).
    bytes12 public gateKeeperId;
    // Who a contributor last delegated to.
    mapping (address => address) private _delegationsByContributor;
    // Array of contributions by a contributor.
    // One is created for every nonzero contribution made.
    mapping (address => Contribution[]) private _contributionsByContributor;
    // Whether the share for split recipient has been claimed through burn().
    bool private _splitRecipientHasBurned;

    constructor(IGlobals globals) PartyCrowdfundNFT(globals) {
        _GLOBALS = globals;
    }

    // Must be called once by freshly deployed PartyCrowdfundProxy instances.
    function _initialize(PartyCrowdfundOptions memory opts)
        internal
    {
        PartyCrowdfundNFT._initialize(opts.name, opts.symbol);
        governanceOptsHash = _hashFixedGovernanceOpts(opts.governanceOpts);
        splitRecipient = opts.splitRecipient;
        splitBps = opts.splitBps;
        // If the deployer passed in some ETH during deployment, credit them.
        uint128 initialBalance = address(this).balance.safeCastUint256ToUint128();
        if (initialBalance > 0) {
            // If this contract has ETH, either passed in during deployment or
            // pre-existing, credit it to the `initialContributor`.
            _contribute(opts.initialContributor, initialBalance, opts.initialDelegate, 0, "");
        }
        // Set up gatekeep after initial contribution (initial always gets in).
        gateKeeper = opts.gateKeeper;
        gateKeeperId = opts.gateKeeperId;
    }

    /// @notice Burns CF tokens owned by `owner` AFTER the CF has ended.
    /// @dev If the party has won, someone needs to call `_createParty()` first. After
    ///      which, `burn()` will refund unused ETH and mint governance tokens for the
    ///      given `contributor`.
    ///      If the party has lost, this will only refund unused ETH (all of it) for
    ///      the given `contributor`.
    function burn(address payable contributor)
        public
    {
        return _burn(contributor, getCrowdfundLifecycle(), party);
    }

    /// @notice `burn()` in batch form.
    function batchBurn(address payable[] calldata contributors)
        external
    {
        Party party_ = party;
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        for (uint256 i = 0; i < contributors.length; ++i) {
            _burn(contributors[i], lc, party_);
        }
    }

    /// @notice Contribute to this crowdfund and/or update your delegation for the
    ///         governance phase should the crowdfund succeed.
    ///         For restricted crowdfunds, `gateData` can be provided to prove
    ///         membership to the gatekeeper.
    function contribute(address delegate, bytes memory gateData)
        public
        payable
    {
        _contribute(
            msg.sender,
            msg.value.safeCastUint256ToUint128(),
            delegate,
            // We cannot use `address(this).balance - msg.value` as the previous
            // total contributions in case someone forces (suicides) ETH into this
            // contract. This wouldn't be such a big deal for open crowdfunds
            // but private ones (protected by a gatekeeper) could be griefed
            // because it would ultimately result in governance power that
            // is unattributed/unclaimable, meaning that party will never be
            // able to reach 100% consensus.
            totalContributions,
            gateData
        );
    }

    /// @notice Contribute, reusing the last delegate of the sender or
    ///         the sender itself if not set.
    receive() external payable {
        // If the sender already delegated before then use that delegate.
        // Otherwise delegate to the sender.
        address delegate = _delegationsByContributor[msg.sender];
        delegate = delegate == address(0) ? msg.sender : delegate;
        _contribute(
            msg.sender,
            msg.value.safeCastUint256ToUint128(),
            delegate,
            totalContributions,
            "" // No gatedata supported with naked contribution
        );
    }

    function supportsInterface(bytes4 interfaceId)
        public
        override(ERC721Receiver, PartyCrowdfundNFT)
        pure
        returns (bool)
    {
        if (ERC721Receiver.supportsInterface(interfaceId)) {
            return true;
        }
        return PartyCrowdfundNFT.supportsInterface(interfaceId);
    }

    /// @notice Retrieve info about a participant's contributions.
    /// @dev This will only be called off-chain so doesn't have to be optimal.
    function getContributorInfo(address contributor)
        external
        view
        returns (
            uint256 ethContributed,
            uint256 ethUsed,
            uint256 ethOwed,
            uint256 votingPower
        )
    {
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        Contribution[] storage contributions = _contributionsByContributor[contributor];
        uint256 numContributions = contributions.length;
        for (uint256 i = 0; i < numContributions; ++i) {
            ethContributed += contributions[i].amount;
        }
        if (lc == CrowdfundLifecycle.Won || lc == CrowdfundLifecycle.Lost) {
            (ethUsed, ethOwed, votingPower) = _getFinalContribution(contributor);
        }
    }

    /// @notice Get the current lifecycle of the crowdfund.
    function getCrowdfundLifecycle() public virtual view returns (CrowdfundLifecycle);

    // Get the final sale price of the bought assets. This will also be the total
    // voting power of the governance party.
    function _getFinalPrice() internal virtual view returns (uint256);

    // Can be called after a party has won.
    // Deploys and initializes a a `Party` instance via the `PartyFactory`
    // and transfers the bought NFT to it.
    // After calling this, anyone can burn CF tokens on a contributor's behalf
    // with the `burn()` function.
    function _createParty(
        IPartyFactory partyFactory,
        FixedGovernanceOpts memory governanceOpts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        internal
        returns (Party party_)
    {
        if (party != Party(payable(0))) {
            revert PartyAlreadyExistsError(party);
        }
        {
            bytes16 governanceOptsHash_ = _hashFixedGovernanceOpts(governanceOpts);
            if (governanceOptsHash_ != governanceOptsHash) {
                revert InvalidGovernanceOptionsError(governanceOptsHash_, governanceOptsHash);
            }
        }
        party = party_ = partyFactory
            .createParty(
                address(this),
                Party.PartyOptions({
                    name: name,
                    symbol: symbol,
                    governance: PartyGovernance.GovernanceOpts({
                        hosts: governanceOpts.hosts,
                        voteDuration: governanceOpts.voteDuration,
                        executionDelay: governanceOpts.executionDelay,
                        passThresholdBps: governanceOpts.passThresholdBps,
                        totalVotingPower: _getFinalPrice().safeCastUint256ToUint96(),
                        feeBps: governanceOpts.feeBps,
                        feeRecipient: governanceOpts.feeRecipient
                    })
                }),
                preciousTokens,
                preciousTokenIds
            );
        // Transfer the acquired NFTs to the new party.
        for (uint256 i = 0; i < preciousTokens.length; ++i) {
            preciousTokens[i].transferFrom(address(this), address(party_), preciousTokenIds[i]);
        }
    }

    // Overloaded single token wrapper for _createParty()
    function _createParty(
        IPartyFactory partyFactory,
        FixedGovernanceOpts memory governanceOpts,
        IERC721 preciousToken,
        uint256 preciousTokenId
    )
        internal
        returns (Party party_)
    {
        IERC721[] memory tokens = new IERC721[](1);
        tokens[0] = preciousToken;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = preciousTokenId;
        return _createParty(partyFactory, governanceOpts, tokens, tokenIds);
    }

    function _hashFixedGovernanceOpts(FixedGovernanceOpts memory opts)
        internal
        pure
        returns (bytes16 h)
    {
        // Hash in place.
        assembly {
            // Replace the address[] hosts field with its hash temporarily.
            let oldHostsFieldValue := mload(opts)
            mstore(opts, keccak256(add(mload(opts), 0x20), mul(mload(mload(opts)), 32)))
            // Hash the entire struct.
            h := and(keccak256(opts, 0xC0), 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000)
            // Restore old hosts field value.
            mstore(opts, oldHostsFieldValue)
        }
    }

    function _getFinalContribution(address contributor)
        internal
        view
        returns (uint256 ethUsed, uint256 ethOwed, uint256 votingPower)
    {
        uint256 totalEthUsed = _getFinalPrice();
        {
            Contribution[] storage contributions = _contributionsByContributor[contributor];
            uint256 numContributions = contributions.length;
            for (uint256 i = 0; i < numContributions; ++i) {
                Contribution memory c = contributions[i];
                if (c.previousTotalContributions >= totalEthUsed) {
                    // This entire contribution was not used.
                    ethOwed += c.amount;
                } else if (c.previousTotalContributions + c.amount <= totalEthUsed) {
                    // This entire contribution was used.
                    ethUsed += c.amount;
                } else {
                    // This contribution was partially used.
                    uint256 partialEthUsed = totalEthUsed - c.previousTotalContributions;
                    ethUsed += partialEthUsed;
                    ethOwed = c.amount - partialEthUsed;
                }
            }
        }
        // one SLOAD with optimizer on
        address splitRecipient_ = splitRecipient;
        uint256 splitBps_ = splitBps;
        if (splitRecipient_ == address(0)) {
            splitBps_ = 0;
        }
        votingPower = ((1e4 - splitBps_) * ethUsed) / 1e4;
        if (splitRecipient_ == contributor) {
            // Split recipient is also the contributor so just add the split
            // voting power.
             votingPower += (splitBps_ * totalEthUsed) / (1e4 - 1); // round up
        }
    }

    function _contribute(
        address contributor,
        uint128 amount,
        address delegate,
        uint128 previousTotalContributions,
        bytes memory gateData
    )
        internal
    {
        if (delegate == address(0)) {
            revert InvalidDelegateError();
        }
        // Must not be blocked by gatekeeper.
        if (gateKeeper != IGateKeeper(address(0))) {
            if (!gateKeeper.isAllowed(contributor, gateKeeperId, gateData)) {
                revert NotAllowedByGateKeeperError(
                    contributor,
                    gateKeeper,
                    gateKeeperId,
                    gateData
                );
            }
        }

        // Increase total contributions.
        totalContributions += amount;
        // Update delegate.
        // OK if this happens out of cycle.
        _delegationsByContributor[contributor] = delegate;
        emit Contributed(contributor, amount, delegate, previousTotalContributions);

        if (amount != 0) {
            // Only allow contributions while the crowdfund is active.
            {
                CrowdfundLifecycle lc = getCrowdfundLifecycle();
                if (lc != CrowdfundLifecycle.Active) {
                    revert WrongLifecycleError(lc);
                }
            }
            // Create contributions entry for this contributor.
            Contribution[] storage contributions = _contributionsByContributor[contributor];
            uint256 numContributions = contributions.length;
            if (numContributions >= 1) {
                Contribution memory lastContribution = contributions[numContributions - 1];
                if (lastContribution.previousTotalContributions == previousTotalContributions) {
                    // No one else has contributed since so just reuse the last entry.
                    lastContribution.amount += amount;
                    contributions[numContributions - 1] = lastContribution;
                    return;
                }
            }
            // Add a new contribution entry.
            contributions.push(Contribution({
                previousTotalContributions: previousTotalContributions,
                amount: amount
            }));
            if (numContributions == 0) {
                // Mint a participation NFT.
                _mint(contributor);
            }
        }
    }

    // Burn the participation NFT for `contributor`, potentially
    // minting voting power and/or refunding unused ETH.
    // `contributor` may also be the split recipient, regardless
    // of whether they are also a contributor or not.
    function _burn(address payable contributor, CrowdfundLifecycle lc, Party party_)
        private
    {
        // If the CF has won, a party must have been created prior.
        if (lc == CrowdfundLifecycle.Won) {
            if (party_ == Party(payable(0))) {
                revert NoPartyError();
            }
        } else {
            // Otherwise it must have lost.
            if (lc != CrowdfundLifecycle.Lost) {
                revert WrongLifecycleError(lc);
            }
        }
        // Split recipient can burn even if they don't have a token.
        if (contributor == splitRecipient) {
            if (_splitRecipientHasBurned) {
                revert SplitRecipientAlreadyBurnedError();
            }
            _splitRecipientHasBurned = true;
        }
        if (splitRecipient != contributor || _doesTokenExistFor(contributor)) {
            // Will revert if already burned or does not exist.
            PartyCrowdfundNFT._burn(contributor);
        }
        (uint256 ethUsed, uint256 ethOwed, uint256 votingPower) =
            _getFinalContribution(contributor);
        if (party_ != Party(payable(0)) && votingPower > 0) {
            address delegate = _delegationsByContributor[contributor];
            if (delegate == address(0)) {
                // Delegate can be unset for the split recipient if they never
                // contribute. Self-delegate if this occurs.
                delegate = contributor;
            }
            _getPartyFactory().mint(
                party_,
                contributor,
                votingPower,
                delegate
            );
        }
        contributor.transferEth(ethOwed);
        emit Burned(contributor, ethUsed, ethOwed, votingPower);
    }

    function _getPartyFactory() internal view returns (IPartyFactory) {
        return IPartyFactory(_GLOBALS.getAddress(LibGlobals.GLOBAL_PARTY_FACTORY));
    }
}
