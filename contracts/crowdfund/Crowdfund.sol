// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../utils/LibAddress.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibSafeCast.sol";
import "../tokens/ERC721Receiver.sol";
import "../party/Party.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";
import "../renderers/RendererStorage.sol";

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
        uint256 customizationPresetId;
        address payable splitRecipient;
        uint16 splitBps;
        address initialContributor;
        address initialDelegate;
        uint96 minContribution;
        uint96 maxContribution;
        IGateKeeper gateKeeper;
        bytes12 gateKeeperId;
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
    error InvalidGovernanceOptionsError();
    error InvalidDelegateError();
    error InvalidContributorError();
    error NoPartyError();
    error NotAllowedByGateKeeperError(
        address contributor,
        IGateKeeper gateKeeper,
        bytes12 gateKeeperId,
        bytes gateData
    );
    error SplitRecipientAlreadyBurnedError();
    error InvalidBpsError(uint16 bps);
    error ExceedsTotalContributionsError(uint96 value, uint96 totalContributions);
    error NothingToClaimError();
    error OnlyPartyHostError();
    error OnlyContributorError();
    error MissingHostsError();
    error OnlyPartyDaoError(address notDao);
    error OnlyPartyDaoOrHostError(address notDao);
    error OnlyWhenEmergencyActionsAllowedError();
    error BelowMinimumContributionsError(uint96 contributions, uint96 minContributions);
    error AboveMaximumContributionsError(uint96 contributions, uint96 maxContributions);

    event Burned(address contributor, uint256 ethUsed, uint256 ethOwed, uint256 votingPower);
    event Contributed(
        address sender,
        address contributor,
        uint256 amount,
        address delegate,
        uint256 previousTotalContributions
    );
    event EmergencyExecute(address target, bytes data, uint256 amountEth);
    event EmergencyExecuteDisabled();

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
    /// @notice Hash of party governance options passed into `initialize()`.
    ///         Used to check whether the `GovernanceOpts` passed into
    ///         `_createParty()` matches.
    bytes32 public governanceOptsHash;
    /// @notice Who a contributor last delegated to.
    mapping(address => address) public delegationsByContributor;
    // Array of contributions by a contributor.
    // One is created for every nonzero contribution made.
    // `internal` for testing purposes only.
    mapping(address => Contribution[]) internal _contributionsByContributor;
    /// @notice Stores the amount of ETH owed back to a contributor and governance NFT
    ///         that should be minted to them if it could not be transferred to
    ///         them with `burn()`.
    mapping(address => Claim) public claims;
    /// @notice Minimum amount of ETH that can be contributed to this crowdfund per address.
    uint96 public minContribution;
    /// @notice Maximum amount of ETH that can be contributed to this crowdfund per address.
    uint96 public maxContribution;
    /// @notice Whether the DAO has emergency powers for this party.
    bool public emergencyExecuteDisabled;

    // Set the `Globals` contract.
    constructor(IGlobals globals) CrowdfundNFT(globals) {
        _GLOBALS = globals;
    }

    // Initialize storage for proxy contracts, credit initial contribution (if
    // any), and setup gatekeeper.
    function _initialize(CrowdfundOptions memory opts) internal {
        CrowdfundNFT._initialize(opts.name, opts.symbol, opts.customizationPresetId);
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
        // Set the minimum and maximum contribution amounts.
        minContribution = opts.minContribution;
        maxContribution = opts.maxContribution;
        // If the deployer passed in some ETH during deployment, credit them
        // for the initial contribution.
        uint96 initialContribution = msg.value.safeCastUint256ToUint96();
        if (initialContribution > 0) {
            _setDelegate(opts.initialContributor, opts.initialDelegate);
            // If this ETH is passed in, credit it to the `initialContributor`.
            _contribute(opts.initialContributor, opts.initialDelegate, initialContribution, 0, "");
        }
        // Set up gatekeeper after initial contribution (initial always gets in).
        gateKeeper = opts.gateKeeper;
        gateKeeperId = opts.gateKeeperId;
    }

    /// @notice As the DAO, execute an arbitrary function call from this contract.
    /// @dev Emergency actions must not be revoked for this to work.
    /// @param targetAddress The contract to call.
    /// @param targetCallData The data to pass to the contract.
    /// @param amountEth The amount of ETH to send to the contract.
    function emergencyExecute(
        address targetAddress,
        bytes calldata targetCallData,
        uint256 amountEth
    ) external payable onlyDelegateCall {
        // Must be called by the DAO.
        if (!_isPartyDao(msg.sender)) {
            revert OnlyPartyDaoError(msg.sender);
        }
        // Must not be disabled by DAO or host.
        if (emergencyExecuteDisabled) {
            revert OnlyWhenEmergencyActionsAllowedError();
        }
        (bool success, bytes memory res) = targetAddress.call{ value: amountEth }(targetCallData);
        if (!success) {
            res.rawRevert();
        }
        emit EmergencyExecute(targetAddress, targetCallData, amountEth);
    }

    /// @notice Revoke the DAO's ability to call emergencyExecute().
    /// @dev Either the DAO or the party host can call this.
    /// @param governanceOpts The fixed governance opts the crowdfund was created with.
    /// @param hostIndex The index of the party host (caller).
    function disableEmergencyExecute(
        FixedGovernanceOpts memory governanceOpts,
        uint256 hostIndex
    ) external onlyDelegateCall {
        // Only the DAO or a host can call this.
        if (!_isHost(msg.sender, governanceOpts, hostIndex) && !_isPartyDao(msg.sender)) {
            revert OnlyPartyDaoOrHostError(msg.sender);
        }
        emergencyExecuteDisabled = true;
        emit EmergencyExecuteDisabled();
    }

    /// @notice Burn the participation NFT for `contributor`, potentially
    ///         minting voting power and/or refunding unused ETH. `contributor`
    ///         may also be the split recipient, regardless of whether they are
    ///         also a contributor or not. This can be called by anyone on a
    ///         contributor's behalf to unlock their voting power in the
    ///         governance stage ensuring delegates receive their voting
    ///         power and governance is not stalled.
    /// @param contributor The contributor whose NFT to burn for.
    function burn(address payable contributor) public {
        return _burn(contributor, getCrowdfundLifecycle(), party);
    }

    /// @dev Alias for `burn()`.
    function activateOrRefund(address payable contributor) external {
        burn(contributor);
    }

    /// @notice `burn()` in batch form.
    ///         Will not revert if any individual burn fails.
    /// @param contributors The contributors whose NFT to burn for.
    /// @param revertOnFailure If true, revert if any burn fails.
    function batchBurn(address payable[] calldata contributors, bool revertOnFailure) public {
        for (uint256 i = 0; i < contributors.length; ++i) {
            (bool s, bytes memory r) = address(this).delegatecall(
                abi.encodeCall(this.burn, (contributors[i]))
            );
            if (revertOnFailure && !s) {
                r.rawRevert();
            }
        }
    }

    /// @dev Alias for `batchBurn()`.
    function batchActivateOrRefund(
        address payable[] calldata contributors,
        bool revertOnFailure
    ) external {
        batchBurn(contributors, revertOnFailure);
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
    function contribute(address delegate, bytes memory gateData) external payable onlyDelegateCall {
        _setDelegate(msg.sender, delegate);

        _contribute(
            msg.sender,
            delegate,
            msg.value.safeCastUint256ToUint96(),
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

    /// @notice Contribute to this crowdfund on behalf of another address.
    /// @param recipient The address to record the contribution under.
    /// @param initialDelegate The address to delegate to for the governance phase if recipient hasn't delegated.
    /// @param gateData Data to pass to the gatekeeper to prove eligibility.
    function contributeFor(
        address recipient,
        address initialDelegate,
        bytes memory gateData
    ) external payable onlyDelegateCall {
        _setDelegate(recipient, initialDelegate);

        _contribute(
            recipient,
            initialDelegate,
            msg.value.safeCastUint256ToUint96(),
            totalContributions,
            gateData
        );
    }

    /// @notice `contributeFor()` in batch form.
    ///         May not revert if any individual contribution fails.
    /// @param recipients The addresses to record the contributions under.
    /// @param initialDelegates The addresses to delegate to for each recipient.
    /// @param values The ETH to contribute for each recipient.
    /// @param gateDatas Data to pass to the gatekeeper to prove eligibility.
    /// @param revertOnFailure If true, revert if any contribution fails.
    function batchContributeFor(
        address[] memory recipients,
        address[] memory initialDelegates,
        uint256[] memory values,
        bytes[] memory gateDatas,
        bool revertOnFailure
    ) external payable {
        for (uint256 i; i < recipients.length; ++i) {
            (bool s, bytes memory r) = address(this).call{ value: values[i] }(
                abi.encodeCall(
                    this.contributeFor,
                    (recipients[i], initialDelegates[i], gateDatas[i])
                )
            );
            if (revertOnFailure && !s) {
                r.rawRevert();
            }
        }
    }

    /// @inheritdoc EIP165
    function supportsInterface(
        bytes4 interfaceId
    ) public pure override(ERC721Receiver, CrowdfundNFT) returns (bool) {
        return
            ERC721Receiver.supportsInterface(interfaceId) ||
            CrowdfundNFT.supportsInterface(interfaceId);
    }

    /// @notice Retrieve info about a participant's contributions.
    /// @dev This will only be called off-chain so doesn't have to be optimal.
    /// @param contributor The contributor to retrieve contributions for.
    /// @return ethContributed The total ETH contributed by `contributor`.
    /// @return ethUsed The total ETH used by `contributor` to acquire the NFT.
    /// @return ethOwed The total ETH refunded back to `contributor`.
    /// @return votingPower The total voting power minted to `contributor`.
    function getContributorInfo(
        address contributor
    )
        external
        view
        returns (uint256 ethContributed, uint256 ethUsed, uint256 ethOwed, uint256 votingPower)
    {
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc == CrowdfundLifecycle.Won || lc == CrowdfundLifecycle.Lost) {
            (ethUsed, ethOwed, votingPower) = _getFinalContribution(contributor);
            ethContributed = ethUsed + ethOwed;
        } else {
            Contribution[] memory contributions = _contributionsByContributor[contributor];
            uint256 numContributions = contributions.length;
            for (uint256 i; i < numContributions; ++i) {
                ethContributed += contributions[i].amount;
            }
        }
    }

    /// @notice Get the current lifecycle of the crowdfund.
    function getCrowdfundLifecycle() public view virtual returns (CrowdfundLifecycle lifecycle);

    // Get the final sale price of the bought assets. This will also be the total
    // voting power of the governance party.
    function _getFinalPrice() internal view virtual returns (uint256);

    // Assert that `who` is a host at `governanceOpts.hosts[hostIndex]` and,
    // if so, assert that the governance opts is the same as the crowdfund
    // was created with.
    // Return true if `governanceOpts` was validated in the process.
    function _assertIsHost(
        address who,
        FixedGovernanceOpts memory governanceOpts,
        uint256 hostIndex
    ) internal view {
        if (!_isHost(who, governanceOpts, hostIndex)) {
            revert OnlyPartyHostError();
        }
    }

    // Check if `who` is a host at `hostIndex` index. Validates governance opts if so.
    function _isHost(
        address who,
        FixedGovernanceOpts memory governanceOpts,
        uint256 hostIndex
    ) private view returns (bool isHost) {
        if (hostIndex < governanceOpts.hosts.length && who == governanceOpts.hosts[hostIndex]) {
            // Validate governance opts if the host was found.
            _assertValidGovernanceOpts(governanceOpts);
            return true;
        }
        return false;
    }

    function _isPartyDao(address who) private view returns (bool isPartyDao) {
        return who == _GLOBALS.getAddress(LibGlobals.GLOBAL_DAO_WALLET);
    }

    // Assert that `who` is a contributor to the crowdfund.
    function _assertIsContributor(address who) internal view {
        if (_contributionsByContributor[who].length == 0) {
            revert OnlyContributorError();
        }
    }

    // Can be called after a party has won.
    // Deploys and initializes a `Party` instance via the `PartyFactory`
    // and transfers the bought NFT to it.
    // After calling this, anyone can burn CF tokens on a contributor's behalf
    // with the `burn()` function.
    function _createParty(
        FixedGovernanceOpts memory governanceOpts,
        bool governanceOptsAlreadyValidated,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) internal returns (Party party_) {
        if (party != Party(payable(0))) {
            revert PartyAlreadyExistsError(party);
        }
        // If the governance opts haven't already been validated, make sure that
        // it hasn't been tampered with.
        if (!governanceOptsAlreadyValidated) {
            _assertValidGovernanceOpts(governanceOpts);
        }
        // Create a party.
        party = party_ = _getPartyFactory().createParty(
            address(this),
            Party.PartyOptions({
                name: name,
                symbol: symbol,
                // Indicates to the party to use the same customization preset as the crowdfund.
                customizationPresetId: 0,
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
        for (uint256 i; i < preciousTokens.length; ++i) {
            preciousTokens[i].transferFrom(address(this), address(party_), preciousTokenIds[i]);
        }
    }

    // Overloaded single token wrapper for _createParty()
    function _createParty(
        FixedGovernanceOpts memory governanceOpts,
        bool governanceOptsAlreadyValidated,
        IERC721 preciousToken,
        uint256 preciousTokenId
    ) internal returns (Party party_) {
        IERC721[] memory tokens = new IERC721[](1);
        tokens[0] = preciousToken;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = preciousTokenId;
        return _createParty(governanceOpts, governanceOptsAlreadyValidated, tokens, tokenIds);
    }

    // Assert that the hash of `opts` matches the hash this crowdfund was initialized with.
    function _assertValidGovernanceOpts(FixedGovernanceOpts memory governanceOpts) private view {
        bytes32 governanceOptsHash_ = _hashFixedGovernanceOpts(governanceOpts);
        if (governanceOptsHash_ != governanceOptsHash) {
            revert InvalidGovernanceOptionsError();
        }
    }

    function _getFinalContribution(
        address contributor
    ) internal view returns (uint256 ethUsed, uint256 ethOwed, uint256 votingPower) {
        uint256 totalEthUsed = _getFinalPrice();
        {
            Contribution[] memory contributions = _contributionsByContributor[contributor];
            uint256 numContributions = contributions.length;
            for (uint256 i; i < numContributions; ++i) {
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

    function _setDelegate(address contributor, address delegate) private {
        if (delegate == address(0)) revert InvalidDelegateError();

        // Only need to update delegate if there was a change.
        address oldDelegate = delegationsByContributor[contributor];
        if (oldDelegate == delegate) return;

        // Only allow setting delegate on another's behalf if the delegate is unset.
        if (msg.sender != contributor && oldDelegate != address(0)) return;

        // Update delegate.
        delegationsByContributor[contributor] = delegate;
    }

    /// @dev While it is not necessary to pass in `delegate` to this because the
    ///      function does not require it, it is here to emit in the
    ///      `Contribute` event so that the PartyBid frontend can access it more
    ///      easily.
    function _contribute(
        address contributor,
        address delegate,
        uint96 amount,
        uint96 previousTotalContributions,
        bytes memory gateData
    ) private {
        if (contributor == address(this)) revert InvalidContributorError();

        if (amount == 0) return;

        // Must not be blocked by gatekeeper.
        {
            IGateKeeper _gateKeeper = gateKeeper;
            if (_gateKeeper != IGateKeeper(address(0))) {
                if (!_gateKeeper.isAllowed(msg.sender, gateKeeperId, gateData)) {
                    revert NotAllowedByGateKeeperError(
                        msg.sender,
                        _gateKeeper,
                        gateKeeperId,
                        gateData
                    );
                }
            }
        }
        // Only allow contributions while the crowdfund is active.
        {
            CrowdfundLifecycle lc = getCrowdfundLifecycle();
            if (lc != CrowdfundLifecycle.Active) {
                revert WrongLifecycleError(lc);
            }
        }
        // Increase total contributions.
        totalContributions += amount;
        // Create contributions entry for this contributor.
        Contribution[] storage contributions = _contributionsByContributor[contributor];
        uint256 numContributions = contributions.length;
        uint96 ethContributed;
        for (uint256 i; i < numContributions; ++i) {
            ethContributed += contributions[i].amount;
        }
        // Check contribution is greater than minimum contribution.
        if (ethContributed + amount < minContribution) {
            revert BelowMinimumContributionsError(ethContributed + amount, minContribution);
        }
        // Check contribution is less than maximum contribution.
        if (ethContributed + amount > maxContribution) {
            revert AboveMaximumContributionsError(ethContributed + amount, maxContribution);
        }

        emit Contributed(msg.sender, contributor, amount, delegate, previousTotalContributions);

        if (numContributions >= 1) {
            Contribution memory lastContribution = contributions[numContributions - 1];
            // If no one else (other than this contributor) has contributed since,
            // we can just reuse this contributor's last entry.
            uint256 totalContributionsAmountForReuse = lastContribution.previousTotalContributions +
                lastContribution.amount;
            if (totalContributionsAmountForReuse == previousTotalContributions) {
                lastContribution.amount += amount;
                contributions[numContributions - 1] = lastContribution;
                return;
            }
        }
        // Add a new contribution entry.
        contributions.push(
            Contribution({ previousTotalContributions: previousTotalContributions, amount: amount })
        );
        // Mint a participation NFT if this is their first contribution.
        if (numContributions == 0) {
            _mint(contributor);
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
        {
            address splitRecipient_ = splitRecipient;
            if (contributor == splitRecipient_) {
                if (_splitRecipientHasBurned) {
                    revert SplitRecipientAlreadyBurnedError();
                }
                _splitRecipientHasBurned = true;
            }
            // Revert if already burned or does not exist.
            if (splitRecipient_ != contributor || _doesTokenExistFor(contributor)) {
                CrowdfundNFT._burn(contributor);
            }
        }
        // Compute the contributions used and owed to the contributor, along
        // with the voting power they'll have in the governance stage.
        (uint256 ethUsed, uint256 ethOwed, uint256 votingPower) = _getFinalContribution(
            contributor
        );
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
        (bool s, ) = contributor.call{ value: ethOwed }("");
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

function _hashFixedGovernanceOpts(
    Crowdfund.FixedGovernanceOpts memory opts
) pure returns (bytes32 h) {
    // Hash in place.
    assembly {
        // Replace the address[] hosts field with its hash temporarily.
        let oldHostsFieldValue := mload(opts)
        mstore(opts, keccak256(add(oldHostsFieldValue, 0x20), mul(mload(oldHostsFieldValue), 32)))
        // Hash the entire struct.
        h := keccak256(opts, 0xC0)
        // Restore old hosts field value.
        mstore(opts, oldHostsFieldValue)
    }
}
