// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../utils/LibAddress.sol";
import "../utils/LibSafeCast.sol";
import "../party/Party.sol";
import "../gatekeepers/IGateKeeper.sol";

contract ETHCrowdfundBase is Implementation {
    using LibRawResult for bytes;
    using LibSafeCast for uint256;
    using LibAddress for address payable;

    enum CrowdfundLifecycle {
        // In practice, this state is never used. If the crowdfund is ever in
        // this stage, something is wrong (e.g. crowdfund was never initialized).
        Invalid,
        // Ready to accept contributions to reach contribution targets
        // until a deadline or the minimum contribution target is reached and
        // host finalizes.
        Active,
        // Expired and the minimum contribution target was not reached.
        Lost,
        // The crowdfund has expired and reached the minimum contribution
        // target. It is now ready to finalize.
        Won,
        // A won crowdfund has been finalized, with funds transferred to the
        // party and voting power successfully updated.
        Finalized
    }

    // Options to be passed into `initialize()` when the crowdfund is created.
    struct ETHCrowdfundOptions {
        Party party;
        address payable initialContributor;
        address initialDelegate;
        uint96 minContribution;
        uint96 maxContribution;
        bool disableContributingForExistingCard;
        uint96 minTotalContributions;
        uint96 maxTotalContributions;
        uint16 exchangeRateBps;
        uint16 fundingSplitBps;
        address payable fundingSplitRecipient;
        uint40 duration;
        IGateKeeper gateKeeper;
        bytes12 gateKeeperId;
    }

    error WrongLifecycleError(CrowdfundLifecycle lc);
    error NotAllowedByGateKeeperError(
        address contributor,
        IGateKeeper gateKeeper,
        bytes12 gateKeeperId,
        bytes gateData
    );
    error OnlyPartyHostError();
    error OnlyPartyDaoError(address notDao);
    error OnlyPartyDaoOrHostError(address notDao);
    error NotOwnerError(uint256 tokenId);
    error OnlyWhenEmergencyActionsAllowedError();
    error InvalidDelegateError();
    error NotEnoughContributionsError(uint96 totalContribution, uint96 minTotalContributions);
    error MinGreaterThanMaxError(uint96 min, uint96 max);
    error MaxTotalContributionsCannotBeZeroError(uint96 maxTotalContributions);
    error BelowMinimumContributionsError(uint96 contributions, uint96 minContributions);
    error AboveMaximumContributionsError(uint96 contributions, uint96 maxContributions);
    error InvalidExchangeRateError(uint16 exchangeRateBps);
    error ContributingForExistingCardDisabledError();
    error ZeroVotingPowerError();
    error FundingSplitAlreadyPaidError();
    error FundingSplitNotConfiguredError();
    error InvalidMessageValue();

    event Contributed(
        address indexed sender,
        address indexed contributor,
        uint256 amount,
        address delegate
    );
    event Finalized();
    event FundingSplitSent(address indexed fundingSplitRecipient, uint256 amount);
    event EmergencyExecuteDisabled();
    event EmergencyExecute(address target, bytes data, uint256 amountEth);

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    /// @notice The address of the `Party` contract instance associated
    ///         with the crowdfund.
    Party public party;
    /// @notice The minimum amount of ETH that a contributor can send to
    ///         participate in the crowdfund.
    uint96 public minContribution;
    /// @notice The maximum amount of ETH that a contributor can send to
    ///         participate in the crowdfund per address.
    uint96 public maxContribution;
    /// @notice A boolean flag that determines whether contributors are allowed
    ///         to increase the voting power of their existing party cards.
    bool public disableContributingForExistingCard;
    /// @notice Whether the funding split has been claimed by the funding split
    ///         recipient.
    bool public fundingSplitPaid;
    /// @notice Whether the DAO has emergency powers for this crowdfund.
    bool public emergencyExecuteDisabled;
    /// @notice The minimum amount of total ETH contributions required for the
    ///         crowdfund to be considered successful.
    uint96 public minTotalContributions;
    /// @notice The maximum amount of total ETH contributions allowed for the
    ///         crowdfund.
    uint96 public maxTotalContributions;
    /// @notice The total amount of ETH contributed to the crowdfund so far.
    uint96 public totalContributions;
    /// @notice The timestamp at which the crowdfund will end or ended. If 0, the
    ///         crowdfund has finalized.
    uint40 public expiry;
    /// @notice The exchange rate to use for converting ETH contributions to
    ///         voting power in basis points (e.g. 10000 = 1:1).
    uint16 public exchangeRateBps;
    /// @notice The portion of contributions to send to the funding recipient in
    ///         basis points (e.g. 100 = 1%).
    uint16 public fundingSplitBps;
    /// @notice The address to which a portion of the contributions is sent to.
    address payable public fundingSplitRecipient;
    /// @notice The gatekeeper contract used to restrict who can contribute to the party.
    IGateKeeper public gateKeeper;
    /// @notice The ID of the gatekeeper to use for restricting contributions to the party.
    bytes12 public gateKeeperId;
    /// @notice The address a contributor is delegating their voting power to.
    mapping(address => address) public delegationsByContributor;

    // Set the `Globals` contract.
    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    // Initialize storage for proxy contracts, credit initial contribution (if
    // any), and setup gatekeeper.
    function _initialize(ETHCrowdfundOptions memory opts) internal {
        // Set the minimum and maximum contribution amounts.
        if (opts.minContribution > opts.maxContribution) {
            revert MinGreaterThanMaxError(opts.minContribution, opts.maxContribution);
        }
        minContribution = opts.minContribution;
        maxContribution = opts.maxContribution;
        // Set the min total contributions.
        if (opts.minTotalContributions > opts.maxTotalContributions) {
            revert MinGreaterThanMaxError(opts.minTotalContributions, opts.maxTotalContributions);
        }
        minTotalContributions = opts.minTotalContributions;
        // Set the max total contributions.
        if (opts.maxTotalContributions == 0) {
            // Prevent this because when `maxTotalContributions` is 0 the
            // crowdfund is invalid in `getCrowdfundLifecycle()` meaning it has
            // never been initialized.
            revert MaxTotalContributionsCannotBeZeroError(opts.maxTotalContributions);
        }
        maxTotalContributions = opts.maxTotalContributions;
        // Set the party crowdfund is for.
        party = opts.party;
        // Set the crowdfund start and end timestamps.
        expiry = uint40(block.timestamp + opts.duration);
        // Set the exchange rate.
        if (opts.exchangeRateBps == 0) revert InvalidExchangeRateError(opts.exchangeRateBps);
        exchangeRateBps = opts.exchangeRateBps;
        // Set the funding split and its recipient.
        fundingSplitBps = opts.fundingSplitBps;
        fundingSplitRecipient = opts.fundingSplitRecipient;
        // Set whether to disable contributing for existing card.
        disableContributingForExistingCard = opts.disableContributingForExistingCard;
    }

    /// @notice Get the current lifecycle of the crowdfund.
    function getCrowdfundLifecycle() public view returns (CrowdfundLifecycle lifecycle) {
        if (maxTotalContributions == 0) {
            return CrowdfundLifecycle.Invalid;
        }

        uint256 expiry_ = expiry;
        if (expiry_ == 0) {
            return CrowdfundLifecycle.Finalized;
        }

        if (block.timestamp >= expiry_) {
            if (totalContributions >= minTotalContributions) {
                return CrowdfundLifecycle.Won;
            } else {
                return CrowdfundLifecycle.Lost;
            }
        }

        return CrowdfundLifecycle.Active;
    }

    function _processContribution(
        address payable contributor,
        address delegate,
        uint96 amount
    ) internal returns (uint96 votingPower) {
        address oldDelegate = delegationsByContributor[contributor];
        if (msg.sender == contributor || oldDelegate == address(0)) {
            // Update delegate.
            delegationsByContributor[contributor] = delegate;
        } else {
            // Prevent changing another's delegate if already delegated.
            delegate = oldDelegate;
        }

        emit Contributed(msg.sender, contributor, amount, delegate);

        // OK to contribute with zero just to update delegate.
        if (amount == 0) return 0;

        // Only allow contributions while the crowdfund is active.
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc != CrowdfundLifecycle.Active) {
            revert WrongLifecycleError(lc);
        }

        // Check that the contribution amount is at or below the maximum.
        uint96 maxContribution_ = maxContribution;
        if (amount > maxContribution_) {
            revert AboveMaximumContributionsError(amount, maxContribution_);
        }

        uint96 newTotalContributions = totalContributions + amount;
        uint96 maxTotalContributions_ = maxTotalContributions;
        if (newTotalContributions >= maxTotalContributions_) {
            totalContributions = maxTotalContributions_;

            // Finalize the crowdfund.
            // This occurs before refunding excess contribution to act as a
            // reentrancy guard.
            _finalize(maxTotalContributions_);

            // Refund excess contribution.
            uint96 refundAmount = newTotalContributions - maxTotalContributions;
            if (refundAmount > 0) {
                amount -= refundAmount;
                payable(msg.sender).transferEth(refundAmount);
            }
        } else {
            totalContributions = newTotalContributions;
        }

        // Check that the contribution amount is at or above the minimum. This
        // is done after `amount` is potentially reduced if refunding excess
        // contribution. There is a case where this prevents a crowdfunds from
        // reaching `maxTotalContributions` if the `minContribution` is greater
        // than the difference between `maxTotalContributions` and the current
        // `totalContributions`. In this scenario users will have to wait until
        // the crowdfund expires or a host finalizes after
        // `minTotalContribution` has been reached by calling `finalize()`.
        uint96 minContribution_ = minContribution;
        if (amount < minContribution_) {
            revert BelowMinimumContributionsError(amount, minContribution_);
        }

        // Subtract fee from contribution amount if applicable.
        address payable fundingSplitRecipient_ = fundingSplitRecipient;
        uint16 fundingSplitBps_ = fundingSplitBps;
        if (fundingSplitRecipient_ != address(0) && fundingSplitBps_ > 0) {
            // Removes funding split from contribution amount in a way that
            // avoids rounding errors for very small contributions <1e4 wei.
            amount = (amount * (1e4 - fundingSplitBps_)) / 1e4;
        }

        // Calculate voting power.
        votingPower = (amount * exchangeRateBps) / 1e4;

        if (votingPower == 0) revert ZeroVotingPowerError();
    }

    /// @notice Calculate the contribution amount from the given voting power.
    /// @param votingPower The voting power to convert to a contribution amount.
    /// @return amount The contribution amount.
    function convertVotingPowerToContribution(
        uint96 votingPower
    ) public view returns (uint96 amount) {
        amount = (votingPower * 1e4) / exchangeRateBps;

        // Add back funding split to contribution amount if applicable.
        address payable fundingSplitRecipient_ = fundingSplitRecipient;
        uint16 fundingSplitBps_ = fundingSplitBps;
        if (fundingSplitRecipient_ != address(0) && fundingSplitBps_ > 0) {
            amount = (amount * 1e4) / (1e4 - fundingSplitBps_);
        }
    }

    function finalize() external {
        uint96 totalContributions_ = totalContributions;

        // Check that the crowdfund is not already finalized.
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc == CrowdfundLifecycle.Active) {
            // Allow host to finalize crowdfund early if it has reached its minimum goal.
            if (!party.isHost(msg.sender)) revert OnlyPartyHostError();

            // Check that the crowdfund has reached its minimum goal.
            uint96 minTotalContributions_ = minTotalContributions;
            if (totalContributions_ < minTotalContributions_) {
                revert NotEnoughContributionsError(totalContributions_, minTotalContributions_);
            }
        } else {
            // Otherwise only allow finalization if the crowdfund has expired
            // and been won. Can be finalized by anyone.
            if (lc != CrowdfundLifecycle.Won) {
                revert WrongLifecycleError(lc);
            }
        }

        // Finalize the crowdfund.
        _finalize(totalContributions_);
    }

    function _finalize(uint96 totalContributions_) internal {
        // Finalize the crowdfund.
        delete expiry;

        // Transfer funding split to recipient if applicable.
        address payable fundingSplitRecipient_ = fundingSplitRecipient;
        uint16 fundingSplitBps_ = fundingSplitBps;
        if (fundingSplitRecipient_ != address(0) && fundingSplitBps_ > 0) {
            totalContributions_ -= (totalContributions_ * fundingSplitBps_) / 1e4;
        }

        // Update the party's total voting power.
        uint96 newVotingPower = (totalContributions_ * exchangeRateBps) / 1e4;
        party.increaseTotalVotingPower(newVotingPower);

        // Transfer ETH to the party.
        payable(address(party)).transferEth(totalContributions_);

        emit Finalized();
    }

    /// @notice Send the funding split to the recipient if applicable.
    function sendFundingSplit() external returns (uint96 splitAmount) {
        // Check that the crowdfund is finalized.
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc != CrowdfundLifecycle.Finalized) revert WrongLifecycleError(lc);

        if (fundingSplitPaid) revert FundingSplitAlreadyPaidError();

        address payable fundingSplitRecipient_ = fundingSplitRecipient;
        uint16 fundingSplitBps_ = fundingSplitBps;
        if (fundingSplitRecipient_ == address(0) || fundingSplitBps_ == 0) {
            revert FundingSplitNotConfiguredError();
        }

        fundingSplitPaid = true;

        // Transfer funding split to recipient.
        splitAmount = (totalContributions * fundingSplitBps_) / 1e4;
        payable(fundingSplitRecipient_).transferEth(splitAmount);

        emit FundingSplitSent(fundingSplitRecipient_, splitAmount);
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
    ) external payable {
        // Must be called by the DAO.
        if (_GLOBALS.getAddress(LibGlobals.GLOBAL_DAO_WALLET) != msg.sender) {
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
    function disableEmergencyExecute() external {
        // Only the DAO or a host can call this.
        if (
            !party.isHost(msg.sender) &&
            _GLOBALS.getAddress(LibGlobals.GLOBAL_DAO_WALLET) != msg.sender
        ) {
            revert OnlyPartyDaoOrHostError(msg.sender);
        }
        emergencyExecuteDisabled = true;
        emit EmergencyExecuteDisabled();
    }
}
