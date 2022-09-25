// SPDX-License-Identifier: Beta Software
// http://ipfs.io/ipfs/QmbGX2MFCaMAsMNMugRFND6DtYygRkwkvrqEyTKhTdBLo5
pragma solidity 0.8.17;

import "../utils/LibAddress.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibSafeCast.sol";
import "../tokens/ERC721Receiver.sol";
import "../party/Party.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

import "./CrowdfundNFT.sol";

// Base contract for AuctionCrowdfund/BuyCrowdfund.
// Holds post-win/loss logic. E.g., burning contribution NFTs and creating a
// party after winning.
abstract contract Crowdfund is Implementation, ERC721Receiver, CrowdfundNFT {
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
    struct CrowdfundOptions {
        string name;
        string symbol;
        address payable splitRecipient;
        uint16 splitBps;
        address initialContributor;
        address initialDelegate;
        IGateKeeper gateKeeper;
        bytes12 gateKeeperId;
        bool onlyHostCanAct;
        FixedGovernanceOpts governanceOpts;
    }

    // A record of a single contribution made by a user.
    // Stored in `_contributionsByContributor`.
    struct Contribution {
        // The value of `Crowdfund.totalContributions` when this contribution was made.
        uint96 previousTotalContributions;
        // How much was this contribution.
        uint96 amount;
    }

    // A record of the refund and governance NFT owed to a contributor if it
    // could not be received by them from `burn()`.
    struct Claim {
        uint256 refund;
        uint256 governanceTokenId;
    }

    error PartyAlreadyExistsError(Party party);
    error WrongLifecycleError(CrowdfundLifecycle lc);
    error InvalidGovernanceOptionsError(bytes32 actualHash, bytes32 expectedHash);
    error InvalidDelegateError();
    error NoPartyError();
    error OnlyContributorAllowedError();
    error NotAllowedByGateKeeperError(address contributor, IGateKeeper gateKeeper, bytes12 gateKeeperId, bytes gateData);
    error SplitRecipientAlreadyBurnedError();
    error InvalidBpsError(uint16 bps);
    error ExceedsTotalContributionsError(uint96 value, uint96 totalContributions);
    error NothingToClaimError();
    error OnlyPartyHostError();
    error OnlyPartyHostOrContributorError();

    event Burned(address contributor, uint256 ethUsed, uint256 ethOwed, uint256 votingPower);
    event Contributed(address contributor, uint256 amount, address delegate, uint256 previousTotalContributions);

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    /// @notice The party instance created by `_createParty()`, if any after a
    ///         successful crowdfund.
    Party public party;
    /// @notice The total (recorded) ETH contributed to this crowdfund.
    uint96 public totalContributions;
    /// @notice The gatekeeper contract to use (if non-null) to restrict who can
    ///         contribute to the party.
    IGateKeeper public gateKeeper;
    /// @notice The ID of the gatekeeper strategy to use.
    bytes12 public gateKeeperId;
    /// @notice Who will receive a reserved portion of governance power when
    ///         the governance party is created.
    address payable public splitRecipient;
    /// @notice How much governance power to reserve for `splitRecipient`,
    ///         in bps, where 10,000 = 100%.
    uint16 public splitBps;
    // Whether the share for split recipient has been claimed through `burn()`.
    bool private _splitRecipientHasBurned;
    /// @notice Whether the party is only allowing host to call `bid()`/`buy()`.
    bool public onlyHostCanAct;
    /// @notice Hash of party governance options passed into `initialize()`.
    ///         Used to check whether the `GovernanceOpts` passed into
    ///         `_createParty()` matches.
    bytes32 public governanceOptsHash;
    /// @notice Who a contributor last delegated to.
    mapping(address => address) public delegationsByContributor;
    // Array of contributions by a contributor.
    // One is created for every nonzero contribution made.
    mapping(address => Contribution[]) private _contributionsByContributor;
    /// @notice Stores the amount of ETH owed back to a contributor and governance NFT
    ///         that should be minted to them if it could not be transferred to
    ///         them with `burn()`.
    mapping(address => Claim) public claims;

    modifier onlyHost(address[] memory hosts) {
        bool isHost;
        for (uint256 i; i < hosts.length; i++) {
            if (hosts[i] == msg.sender) {
                isHost = true;
                break;
            }
        }

        if (!isHost) {
            revert OnlyPartyHostError();
        }

        _;
    }

    // Checks whether a function is allowed to be called by caller based on
    // whether `onlyHostCanAct` or crowdfund is using a gatekeeper. If the
    // crowdfund is using `onlyHostCanAct`, then only hosts can call the
    // function. If the crowdfund is using a gatekeeper, then only contributors
    // or hosts can call the function. Otherwise, anyone can call the function.
    modifier checkIfOnlyHostOrContributor(address[] memory hosts) {
        bool onlyHostCanAct_ = onlyHostCanAct;
        if (
            // Check if only allowing host to call.
            onlyHostCanAct_ ||
            // Otherwise, check if the gatekeeper is used. If so, only allow either
            // contributors or host to call.
            (address(gateKeeper) != address(0) &&
            _contributionsByContributor[msg.sender].length == 0)
        ) {
            bool isHost;
            for (uint256 i; i < hosts.length; i++) {
                if (hosts[i] == msg.sender) {
                    isHost = true;
                    break;
                }
            }

            if (!isHost) {
                if (onlyHostCanAct_) {
                    // Not a host.
                    revert OnlyPartyHostError();
                } else {
                    // Neither host or contributor.
                    revert OnlyPartyHostOrContributorError();
                }
            }
        }

        _;
    }

    // Set the `Globals` contract.
    constructor(IGlobals globals) CrowdfundNFT(globals) {
        _GLOBALS = globals;
    }

    // Initialize storage for proxy contracts, credit initial contribution (if
    // any), and setup gatekeeper.
    function _initialize(CrowdfundOptions memory opts)
        internal
    {
        CrowdfundNFT._initialize(opts.name, opts.symbol);
        // Check that BPS values do not exceed the max.
        if (opts.governanceOpts.feeBps > 1e4) {
            revert InvalidBpsError(opts.governanceOpts.feeBps);
        }
        if (opts.governanceOpts.passThresholdBps > 1e4) {
            revert InvalidBpsError(opts.governanceOpts.passThresholdBps);
        }
        if (opts.splitBps > 1e4) {
            revert InvalidBpsError(opts.splitBps);
        }
        governanceOptsHash = _hashFixedGovernanceOpts(opts.governanceOpts);
        splitRecipient = opts.splitRecipient;
        splitBps = opts.splitBps;
        onlyHostCanAct = opts.onlyHostCanAct;
        // If the deployer passed in some ETH during deployment, credit them
        // for the initial contribution.
        uint96 initialBalance = address(this).balance.safeCastUint256ToUint96();
        if (initialBalance > 0) {
            // If this contract has ETH, either passed in during deployment or
            // pre-existing, credit it to the `initialContributor`.
            _contribute(opts.initialContributor, initialBalance, opts.initialDelegate, 0, "");
        }
        // Set up gatekeeper after initial contribution (initial always gets in).
        gateKeeper = opts.gateKeeper;
        gateKeeperId = opts.gateKeeperId;
    }

    /// @notice Burn the participation NFT for `contributor`, potentially
    ///         minting voting power and/or refunding unused ETH. `contributor`
    ///         may also be the split recipient, regardless of whether they are
    ///         also a contributor or not. This can be called by anyone on a
    ///         contributor's behalf to unlock their voting power in the
    ///         governance stage ensuring delegates receive their voting
    ///         power and governance is not stalled.
    /// @dev If the party has won, someone needs to call `_createParty()` first. After
    ///      which, `burn()` will refund unused ETH and mint governance tokens for the
    ///      given `contributor`.
    ///      If the party has lost, this will only refund unused ETH (all of it) for
    ///      the given `contributor`.
    /// @param contributor The contributor whose NFT to burn for.
    function burn(address payable contributor) external {
        return _burn(contributor, getCrowdfundLifecycle(), party);
    }

    /// @notice `burn()` in batch form.
    /// @param contributors The contributors whose NFT to burn for.
    function batchBurn(address payable[] calldata contributors) external {
        Party party_ = party;
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        for (uint256 i = 0; i < contributors.length; ++i) {
            _burn(contributors[i], lc, party_);
        }
    }

    /// @notice Claim a governance NFT or refund that is owed back but could not be
    ///         given due to error in `_burn()` (eg. a contract that does not
    ///         implement `onERC721Received()` or cannot receive ETH). Only call
    ///         this if refund and governance NFT minting could not be returned
    ///         with `burn()`.
    /// @param receiver The address to receive the NFT or refund.
    function claim(address payable receiver) external {
        Claim memory claimInfo = claims[msg.sender];
        delete claims[msg.sender];

        if (claimInfo.refund == 0 && claimInfo.governanceTokenId == 0) {
            revert NothingToClaimError();
        }

        if (claimInfo.refund != 0) {
            receiver.transferEth(claimInfo.refund);
        }

        if (claimInfo.governanceTokenId != 0) {
            party.safeTransferFrom(address(this), receiver, claimInfo.governanceTokenId);
        }
    }

    /// @notice Contribute to this crowdfund and/or update your delegation for the
    ///         governance phase should the crowdfund succeed.
    ///         For restricted crowdfunds, `gateData` can be provided to prove
    ///         membership to the gatekeeper.
    /// @param delegate The address to delegate to for the governance phase.
    /// @param gateData Data to pass to the gatekeeper to prove eligibility.
    function contribute(address delegate, bytes memory gateData)
        public
        payable
        onlyDelegateCall
    {
        _contribute(
            msg.sender,
            msg.value.safeCastUint256ToUint96(),
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

    /// @inheritdoc EIP165
    function supportsInterface(bytes4 interfaceId)
        public
        override(ERC721Receiver, CrowdfundNFT)
        pure
        returns (bool)
    {
        return ERC721Receiver.supportsInterface(interfaceId) ||
            CrowdfundNFT.supportsInterface(interfaceId);
    }

    /// @notice Retrieve info about a participant's contributions.
    /// @dev This will only be called off-chain so doesn't have to be optimal.
    /// @param contributor The contributor to retrieve contributions for.
    /// @return ethContributed The total ETH contributed by `contributor`.
    /// @return ethUsed The total ETH used by `contributor` to acquire the NFT.
    /// @return ethOwed The total ETH refunded back to `contributor`.
    /// @return votingPower The total voting power minted to `contributor`.
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
            bytes32 governanceOptsHash_ = _hashFixedGovernanceOpts(governanceOpts);
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
        returns (bytes32 h)
    {
        // Hash in place.
        assembly {
            // Replace the address[] hosts field with its hash temporarily.
            let oldHostsFieldValue := mload(opts)
            mstore(opts, keccak256(add(mload(opts), 0x20), mul(mload(mload(opts)), 32)))
            // Hash the entire struct.
            h := keccak256(opts, 0xC0)
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
            votingPower += (splitBps_ * totalEthUsed + (1e4 - 1)) / 1e4; // round up
        }
    }

    function _contribute(
        address contributor,
        uint96 amount,
        address delegate,
        uint96 previousTotalContributions,
        bytes memory gateData
    )
        internal
    {
        // Require a non-null delegate.
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

        // Update delegate.
        // OK if this happens out of cycle.
        delegationsByContributor[contributor] = delegate;
        emit Contributed(contributor, amount, delegate, previousTotalContributions);

        // OK to contribute with zero just to update delegate.
        if (amount != 0) {
            // Increase total contributions.
            totalContributions += amount;

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
            // Mint a participation NFT if this is their first contribution.
            if (numContributions == 0) {
                _mint(contributor);
            }
        }
    }

    function _burn(address payable contributor, CrowdfundLifecycle lc, Party party_) private {
        // If the CF has won, a party must have been created prior.
        if (lc == CrowdfundLifecycle.Won) {
            if (party_ == Party(payable(0))) {
                revert NoPartyError();
            }
        } else if (lc != CrowdfundLifecycle.Lost) {
            // Otherwise it must have lost.
            revert WrongLifecycleError(lc);
        }
        // Split recipient can burn even if they don't have a token.
        if (contributor == splitRecipient) {
            if (_splitRecipientHasBurned) {
                revert SplitRecipientAlreadyBurnedError();
            }
            _splitRecipientHasBurned = true;
        }
        // Revert if already burned or does not exist.
        if (splitRecipient != contributor || _doesTokenExistFor(contributor)) {
            CrowdfundNFT._burn(contributor);
        }
        // Compute the contributions used and owed to the contributor, along
        // with the voting power they'll have in the governance stage.
        (uint256 ethUsed, uint256 ethOwed, uint256 votingPower) =
            _getFinalContribution(contributor);
        if (votingPower > 0) {
            // Get the address to delegate voting power to. If null, delegate to self.
            address delegate = delegationsByContributor[contributor];
            if (delegate == address(0)) {
                // Delegate can be unset for the split recipient if they never
                // contribute. Self-delegate if this occurs.
                delegate = contributor;
            }
            // Mint governance NFT for the contributor.
            try party_.mint(contributor, votingPower, delegate) returns (uint256) {
                // OK
            } catch {
                // Mint to the crowdfund itself to escrow for contributor to
                // come claim later on.
                uint256 tokenId = party_.mint(address(this), votingPower, delegate);
                claims[contributor].governanceTokenId = tokenId;
            }
        }
        // Refund any ETH owed back to the contributor.
        (bool s, ) = contributor.call{value: ethOwed}("");
        if (!s) {
            // If the transfer fails, the contributor can still come claim it
            // from the crowdfund.
            claims[contributor].refund = ethOwed;
        }
        emit Burned(contributor, ethUsed, ethOwed, votingPower);
    }

    function _getPartyFactory() internal view returns (IPartyFactory) {
        return IPartyFactory(_GLOBALS.getAddress(LibGlobals.GLOBAL_PARTY_FACTORY));
    }
}
