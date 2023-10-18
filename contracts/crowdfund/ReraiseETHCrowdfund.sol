// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./ETHCrowdfundBase.sol";
import "../crowdfund/CrowdfundNFT.sol";
import "../utils/LibAddress.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibSafeCast.sol";
import "../party/Party.sol";
import "../globals/IGlobals.sol";
import "../gatekeepers/IGateKeeper.sol";

/// @notice A crowdfund for raising additional funds for an existing parties.
contract ReraiseETHCrowdfund is ETHCrowdfundBase, CrowdfundNFT {
    using LibRawResult for bytes;
    using LibSafeCast for uint256;
    using LibAddress for address payable;

    struct BatchContributeArgs {
        // The address to which voting power will be delegated for all contributions.
        address delegate;
        // The contribution amounts in wei. The length of this array must be
        // equal to the length of `tokenIds`.
        uint96[] values;
        // The data required to be validated by the `gatekeeper`, if set. If no
        // `gatekeeper` is set, this can be empty.
        bytes[] gateDatas;
    }

    struct BatchContributeForArgs {
        // Addresses of to credit the contributions under. Each contribution
        // amount in `values` corresponds to a recipient in this array.
        address payable[] recipients;
        // The delegate to set for each recipient if they have not delegated
        // before.
        address[] initialDelegates;
        // The contribution amounts in wei. The length of this array must be
        // equal to the length of `recipients`.
        uint96[] values;
        // The data required to be validated by the `gatekeeper`, if set. If no
        // `gatekeeper` is set, this can be empty.
        bytes[] gateDatas;
    }

    event Claimed(address indexed contributor, uint256 indexed tokenId, uint256 votingPower);
    event Refunded(address indexed contributor, uint256 amount);

    error RemainingVotingPowerAfterClaimError(uint256 remainingVotingPower);

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    /// @notice The amount of voting power that will be received by a
    ///         contributor after the crowdfund is won.
    mapping(address => uint96) public pendingVotingPower;

    // Set the `Globals` contract.
    constructor(IGlobals globals) CrowdfundNFT(globals) ETHCrowdfundBase(globals) {
        _GLOBALS = globals;
    }

    /// @notice Initializer to be delegatecalled by `Proxy` constructor. Will
    ///         revert if called outside the constructor.
    /// @param opts The options to initialize the crowdfund with.
    function initialize(ETHCrowdfundOptions memory opts) external payable onlyInitialize {
        // Initialize the crowdfund.
        ETHCrowdfundBase._initialize(opts);

        // Initialize the crowdfund NFT.
        _initialize(
            opts.party.name(),
            opts.party.symbol(),
            0 // Ignored. Will use customization preset from party.
        );

        // If the deployer passed in some ETH during deployment, credit them
        // for the initial contribution.
        uint96 initialContribution = msg.value.safeCastUint256ToUint96();
        if (initialContribution > 0) {
            // If this contract has ETH, either passed in during deployment or
            // pre-existing, credit it to the `initialContributor`.
            _contribute(opts.initialContributor, opts.initialDelegate, initialContribution, "");
        }

        // Set up gatekeeper after initial contribution (initial always gets in).
        gateKeeper = opts.gateKeeper;
        gateKeeperId = opts.gateKeeperId;
    }

    // Initialize name and symbol for crowdfund NFT.
    function _initialize(string memory name_, string memory symbol_, uint256) internal override {
        name = name_;
        symbol = symbol_;

        RendererStorage rendererStorage = RendererStorage(
            _GLOBALS.getAddress(LibGlobals.GLOBAL_RENDERER_STORAGE)
        );

        // Use the same customization preset as the party.
        uint256 customizationPresetId = rendererStorage.getPresetFor(address(party));
        if (customizationPresetId != 0) {
            rendererStorage.useCustomizationPreset(customizationPresetId);
        }
    }

    /// @notice Contribute ETH to this crowdfund on behalf of a contributor.
    /// @param delegate The address to which voting power will be delegated to
    ///                 during the governance phase.
    /// @param gateData Data to pass to the gatekeeper to prove eligibility.
    /// @return votingPower The voting power the contributor receives for their
    ///                     contribution.
    function contribute(
        address delegate,
        bytes memory gateData
    ) public payable onlyDelegateCall returns (uint96 votingPower) {
        return
            _contribute(
                payable(msg.sender),
                delegate,
                msg.value.safeCastUint256ToUint96(),
                gateData
            );
    }

    /// @notice `contribute()` in batch form.
    ///         May not revert if any individual contribution fails.
    /// @param args The arguments to pass to each `contribute()` call.
    /// @return votingPowers The voting power received for each contribution.
    function batchContribute(
        BatchContributeArgs calldata args
    ) external payable onlyDelegateCall returns (uint96[] memory votingPowers) {
        uint256 numContributions = args.values.length;
        votingPowers = new uint96[](numContributions);

        uint256 ethAvailable = msg.value;
        for (uint256 i; i < numContributions; ++i) {
            ethAvailable -= args.values[i];

            votingPowers[i] = _contribute(
                payable(msg.sender),
                args.delegate,
                args.values[i],
                args.gateDatas[i]
            );
        }

        // Refund any unused ETH.
        if (ethAvailable > 0) payable(msg.sender).transfer(ethAvailable);
    }

    /// @notice Contribute to this crowdfund on behalf of another address.
    /// @param recipient The address to record the contribution under
    /// @param initialDelegate The address to delegate to for the governance
    ///                        phase if recipient hasn't delegated
    /// @param gateData Data to pass to the gatekeeper to prove eligibility
    /// @return votingPower The voting power received for the contribution
    function contributeFor(
        address payable recipient,
        address initialDelegate,
        bytes memory gateData
    ) external payable onlyDelegateCall returns (uint96 votingPower) {
        return
            _contribute(recipient, initialDelegate, msg.value.safeCastUint256ToUint96(), gateData);
    }

    /// @notice `contributeFor()` in batch form.
    ///         May not revert if any individual contribution fails.
    /// @param args The arguments for the batched `contributeFor()` calls.
    /// @return votingPowers The voting power received for each contribution.
    function batchContributeFor(
        BatchContributeForArgs memory args
    ) external payable onlyDelegateCall returns (uint96[] memory votingPowers) {
        votingPowers = new uint96[](args.recipients.length);
        uint256 valuesSum;
        for (uint256 i; i < args.recipients.length; ++i) {
            votingPowers[i] = _contribute(
                args.recipients[i],
                args.initialDelegates[i],
                args.values[i],
                args.gateDatas[i]
            );
            valuesSum += args.values[i];
        }
        if (msg.value != valuesSum) {
            revert InvalidMessageValue();
        }
    }

    function _contribute(
        address payable contributor,
        address delegate,
        uint96 amount,
        bytes memory gateData
    ) private returns (uint96 votingPower) {
        // Require a non-null delegate.
        if (delegate == address(0)) {
            revert InvalidDelegateError();
        }

        // Must not be blocked by gatekeeper.
        IGateKeeper _gateKeeper = gateKeeper;
        if (_gateKeeper != IGateKeeper(address(0))) {
            if (!_gateKeeper.isAllowed(msg.sender, gateKeeperId, gateData)) {
                revert NotAllowedByGateKeeperError(
                    contributor,
                    _gateKeeper,
                    gateKeeperId,
                    gateData
                );
            }
        }

        votingPower = _processContribution(contributor, delegate, amount);

        // OK to contribute with zero just to update delegate.
        if (amount == 0) return 0;

        uint256 previousVotingPower = pendingVotingPower[contributor];

        pendingVotingPower[contributor] += votingPower;

        // Mint a crowdfund NFT if this is their first contribution.
        if (previousVotingPower == 0) _mint(contributor);
    }

    /// @notice Claim a party card for a contributor if the crowdfund won. Can be called
    ///         to claim for self or on another's behalf.
    /// @param contributor The contributor to claim for.
    function claim(address contributor) external {
        claim(
            0, // Mint a new party card.
            contributor
        );
    }

    /// @notice Claim a party card for a contributor if the crowdfund won. Can be called
    ///         to claim for self or on another's behalf.
    /// @param tokenId The ID of the party card to add voting power to. If 0, a
    ///                new card will be minted.
    /// @param contributor The contributor to claim for.
    function claim(uint256 tokenId, address contributor) public {
        // Check crowdfund lifecycle.
        {
            CrowdfundLifecycle lc = getCrowdfundLifecycle();
            if (lc != CrowdfundLifecycle.Finalized) {
                revert WrongLifecycleError(lc);
            }
        }

        uint96 votingPower = pendingVotingPower[contributor];

        if (votingPower == 0) return;

        {
            uint96 contribution = convertVotingPowerToContribution(votingPower);
            uint96 maxContribution_ = maxContribution;
            // Check that the contribution equivalent of total pending voting
            // power is not above the max contribution range. This can happen
            // for contributors who contributed multiple times In this case, the
            // `claimMultiple` function should be called instead. This is done
            // so parties may use the minimum and maximum contribution values to
            // limit the voting power of each card (e.g.  a party desiring a "1
            // card = 1 vote"-like governance system where each card has equal
            // voting power).
            if (contribution > maxContribution_) {
                revert AboveMaximumContributionsError(contribution, maxContribution_);
            }
        }

        // Burn the crowdfund NFT.
        _burn(contributor);

        delete pendingVotingPower[contributor];

        if (tokenId == 0) {
            // Mint contributor a new party card.
            tokenId = party.mint(contributor, votingPower, delegationsByContributor[contributor]);
        } else if (disableContributingForExistingCard) {
            revert ContributingForExistingCardDisabledError();
        } else if (party.ownerOf(tokenId) == contributor) {
            // Increase voting power of contributor's existing party card.
            party.increaseVotingPower(tokenId, votingPower);
        } else {
            revert NotOwnerError(tokenId);
        }

        emit Claimed(contributor, tokenId, votingPower);
    }

    /// @notice `claim()` in batch form.
    ///         May not revert if any individual refund fails.
    /// @param tokenIds The IDs of the party cards to add voting power to. If 0, a
    ///                 new card will be minted.
    /// @param contributors The contributors to claim for.
    /// @param revertOnFailure If true, reverts if any individual claim fails.
    function batchClaim(
        uint256[] calldata tokenIds,
        address[] calldata contributors,
        bool revertOnFailure
    ) external {
        for (uint256 i; i < contributors.length; ++i) {
            (bool s, bytes memory r) = address(this).call(
                // Using `abi.encodeWithSignature()` instead of `abi.encodeCall()`
                // because `abi.encodeCall()` doesn't support overloaded functions.
                abi.encodeWithSignature("claim(uint256,address)", tokenIds[i], contributors[i])
            );
            if (revertOnFailure && !s) {
                r.rawRevert();
            }
        }
    }

    /// @notice Claim multiple party cards for a contributor if the crowdfund won. Can be called
    ///         to claim for self or on another's behalf.
    /// @param votingPowerByCard The voting power for each card claimed. Must add up to the
    ///                          total pending voting power for the contributor.
    /// @param tokenIds The IDs of the party cards to add voting power to. If 0,
    ///                 a new card will be minted.
    /// @param contributor The contributor to claim for.
    function claimMultiple(
        uint96[] memory votingPowerByCard,
        uint256[] memory tokenIds,
        address contributor
    ) external {
        // Check crowdfund lifecycle.
        {
            CrowdfundLifecycle lc = getCrowdfundLifecycle();
            if (lc != CrowdfundLifecycle.Finalized) {
                revert WrongLifecycleError(lc);
            }
        }

        uint256 votingPower = pendingVotingPower[contributor];

        if (votingPower == 0) return;

        // Burn the crowdfund NFT.
        _burn(contributor);

        delete pendingVotingPower[contributor];

        address delegate = delegationsByContributor[contributor];
        uint96 minContribution_ = minContribution;
        uint96 maxContribution_ = maxContribution;
        for (uint256 i; i < votingPowerByCard.length; ++i) {
            uint96 votingPowerForCard = votingPowerByCard[i];

            if (votingPowerForCard == 0) continue;

            // Check that the contribution equivalent of voting power is within
            // contribution range. This is done so parties may use the minimum
            // and maximum contribution values to limit the voting power of each
            // card (e.g. a party desiring a "1 card = 1 vote"-like governance
            // system where each card has equal voting power).
            uint96 contribution = convertVotingPowerToContribution(votingPowerByCard[i]);
            if (contribution < minContribution_) {
                revert BelowMinimumContributionsError(contribution, minContribution_);
            }

            if (contribution > maxContribution_) {
                revert AboveMaximumContributionsError(contribution, maxContribution_);
            }

            votingPower -= votingPowerForCard;

            uint256 tokenId = tokenIds[i];
            if (tokenId == 0) {
                // Mint contributor a new party card.
                tokenId = party.mint(contributor, votingPowerForCard, delegate);
            } else if (disableContributingForExistingCard) {
                revert ContributingForExistingCardDisabledError();
            } else if (party.ownerOf(tokenId) == contributor) {
                // Increase voting power of contributor's existing party card.
                party.increaseVotingPower(tokenId, votingPowerForCard);
            } else {
                revert NotOwnerError(tokenId);
            }

            emit Claimed(contributor, tokenId, votingPowerForCard);
        }

        // Requires that all voting power is claimed because the contributor is
        // expected to have burned their crowdfund NFT.
        if (votingPower != 0) revert RemainingVotingPowerAfterClaimError(votingPower);
    }

    /// @notice `claimMultiple()` in batch form.
    ///         May not revert if any individual refund fails.
    /// @param votingPowerByCards The voting power for each card claimed for each
    ///                           contributor. Must add up to the total pending
    ///                           voting power for the contributor.
    /// @param tokenIds The IDs of the party cards to add voting power to for each
    ///                 contributor. If 0, a new card will be minted.
    /// @param contributors The contributors to claim for.
    /// @param revertOnFailure If true, reverts if any individual claim fails.
    function batchClaimMultiple(
        uint96[][] calldata votingPowerByCards,
        uint256[][] calldata tokenIds,
        address[] calldata contributors,
        bool revertOnFailure
    ) external {
        for (uint256 i; i < contributors.length; ++i) {
            (bool s, bytes memory r) = address(this).call(
                abi.encodeCall(
                    this.claimMultiple,
                    (votingPowerByCards[i], tokenIds[i], contributors[i])
                )
            );
            if (revertOnFailure && !s) {
                r.rawRevert();
            }
        }
    }

    /// @notice Refund the owner of a party card and burn it. Only available if
    ///         the crowdfund lost. Can be called to refund for self or on
    ///         another's behalf.
    /// @param contributor The contributor to refund.
    function refund(address payable contributor) external returns (uint96 amount) {
        // Check crowdfund lifecycle.
        {
            CrowdfundLifecycle lc = getCrowdfundLifecycle();
            if (lc != CrowdfundLifecycle.Lost) {
                revert WrongLifecycleError(lc);
            }
        }

        // Get amount to refund.
        uint96 votingPower = pendingVotingPower[contributor];
        amount = convertVotingPowerToContribution(votingPower);

        if (amount == 0) return 0;

        // Burn the crowdfund NFT.
        _burn(contributor);

        delete pendingVotingPower[contributor];

        // Refund contributor.
        contributor.transferEth(amount);

        emit Refunded(contributor, amount);
    }

    /// @notice `refund()` in batch form.
    ///         May not revert if any individual refund fails.
    /// @param contributors The contributors to refund.
    /// @param revertOnFailure If true, revert if any refund fails.
    /// @return amounts The amounts of ETH refunded for each refund.
    function batchRefund(
        address payable[] calldata contributors,
        bool revertOnFailure
    ) external returns (uint96[] memory amounts) {
        uint256 numRefunds = contributors.length;
        amounts = new uint96[](numRefunds);

        for (uint256 i; i < numRefunds; ++i) {
            (bool s, bytes memory r) = address(this).call(
                abi.encodeCall(this.refund, (contributors[i]))
            );

            if (!s) {
                if (revertOnFailure) {
                    r.rawRevert();
                }
            } else {
                amounts[i] = abi.decode(r, (uint96));
            }
        }
    }
}
