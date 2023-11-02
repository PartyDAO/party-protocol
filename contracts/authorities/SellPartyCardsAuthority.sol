// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "contracts/party/Party.sol";
import "contracts/gatekeepers/IGateKeeper.sol";

// TODO: Use named imports
// TODO: Update contribution router to support batch contributions
// TODO: Document that exchangeRateBps may be greater than 1e4 (100%)

contract SellPartyCardsAuthority {
    using LibSafeCast for uint96;
    using LibSafeCast for uint256;
    using LibAddress for address payable;

    struct FixedMembershipSaleOpts {
        uint96 pricePerMembership;
        uint96 votingPowerPerMembership;
        uint96 totalMembershipsForSale;
        uint16 fundingSplitBps;
        address payable fundingSplitRecipient;
        uint40 duration;
        IGateKeeper gateKeeper;
        bytes12 gateKeeperId;
    }

    struct FlexibleMembershipSaleOpts {
        uint96 minContribution;
        uint96 maxContribution;
        uint96 maxTotalContributions;
        uint16 exchangeRateBps;
        uint16 fundingSplitBps;
        address payable fundingSplitRecipient;
        uint40 duration;
        IGateKeeper gateKeeper;
        bytes12 gateKeeperId;
    }

    struct SaleState {
        uint96 minContribution;
        uint96 maxContribution;
        uint96 totalContributions;
        uint96 maxTotalContributions;
        uint16 exchangeRateBps;
        uint16 fundingSplitBps;
        address payable fundingSplitRecipient;
        uint40 expiry;
        IGateKeeper gateKeeper;
        bytes12 gateKeeperId;
    }

    struct BatchContributeArgs {
        Party party;
        uint256 saleId;
        address delegate;
        uint96[] values;
        bytes gateData;
    }

    struct BatchContributeForArgs {
        Party party;
        uint256 saleId;
        address[] recipients;
        address[] initialDelegates;
        uint96[] values;
        bytes gateData;
    }

    mapping(Party party => uint256 lastId) public lastSaleId;
    mapping(Party party => mapping(uint256 id => SaleState opts)) public saleStates;

    event CreatedSale(Party party, uint256 saleId);
    event Finalized(Party party, uint256 saleId);
    event Contributed(address sender, address contributor, uint96 amount, address delegate);

    error MinGreaterThanMaxError(uint96 minContribution, uint96 maxContribution);
    error ZeroMaxTotalContributionsError();
    error ZeroExchangeRateBpsError();
    error InvalidBpsError(uint16 fundingSplitBps);
    error ZeroVotingPowerError();
    error InvalidMessageValue();
    error OnlyPartyHostError();
    error SaleInactiveError();
    error InvalidDelegateError();
    error NotAllowedByGateKeeperError(
        address sender,
        IGateKeeper gateKeeper,
        bytes12 gateKeeperId,
        bytes gateData
    );
    error AboveMaximumContributionsError(uint96 amount, uint96 maxContribution);
    error BelowMinimumContributionsError(uint96 amount, uint96 minContribution);

    function createFixedMembershipSale(
        FixedMembershipSaleOpts calldata opts
    ) external returns (uint256 saleId) {
        return
            _createSale(
                SaleState({
                    minContribution: opts.pricePerMembership,
                    maxContribution: opts.pricePerMembership,
                    totalContributions: 0,
                    maxTotalContributions: opts.pricePerMembership * opts.totalMembershipsForSale,
                    exchangeRateBps: ((opts.votingPowerPerMembership * 1e4) /
                        opts.pricePerMembership).safeCastUint96ToUint16(),
                    fundingSplitBps: opts.fundingSplitBps,
                    fundingSplitRecipient: opts.fundingSplitRecipient,
                    expiry: uint40(block.timestamp + opts.duration),
                    gateKeeper: opts.gateKeeper,
                    gateKeeperId: opts.gateKeeperId
                })
            );
    }

    function createFlexibleMembershipSale(
        FlexibleMembershipSaleOpts calldata opts
    ) external returns (uint256 saleId) {
        return
            _createSale(
                SaleState({
                    minContribution: opts.minContribution,
                    maxContribution: opts.maxContribution,
                    totalContributions: 0,
                    maxTotalContributions: opts.maxTotalContributions,
                    exchangeRateBps: opts.exchangeRateBps,
                    fundingSplitBps: opts.fundingSplitBps,
                    fundingSplitRecipient: opts.fundingSplitRecipient,
                    expiry: uint40(block.timestamp + opts.duration),
                    gateKeeper: opts.gateKeeper,
                    gateKeeperId: opts.gateKeeperId
                })
            );
    }

    function _createSale(SaleState memory state) private returns (uint256 saleId) {
        if (state.minContribution > state.maxContribution)
            revert MinGreaterThanMaxError(state.minContribution, state.maxContribution);
        if (state.maxTotalContributions == 0) revert ZeroMaxTotalContributionsError();
        if (state.exchangeRateBps == 0) revert ZeroExchangeRateBpsError();
        if (state.fundingSplitBps > 1e4) revert InvalidBpsError(state.fundingSplitBps);

        Party party = Party(payable(msg.sender));
        saleId = ++lastSaleId[party];
        saleStates[party][saleId] = state;

        emit CreatedSale(party, saleId);
    }

    function contribute(
        Party party,
        uint256 saleId,
        address delegate,
        bytes calldata gateData
    ) external payable returns (uint96 votingPower) {
        SaleState memory state = saleStates[party][saleId];

        // TODO: Check that _beforeContribute here works as expected
        delegate = _beforeContribute(
            party,
            msg.sender,
            delegate,
            state.gateKeeper,
            state.gateKeeperId,
            gateData
        );

        // TODO: Check that _contribute here works as expected
        votingPower = _contribute(party, saleId, state, msg.sender, delegate, uint96(msg.value));

        if (votingPower == 0) revert ZeroVotingPowerError();

        // Mint contributor a new party card.
        party.increaseTotalVotingPower(votingPower);
        party.mint(msg.sender, votingPower, delegate);
    }

    function contributeFor(
        Party party,
        uint256 saleId,
        address recipient,
        address initialDelegate,
        bytes calldata gateData
    ) external payable returns (uint96 votingPower) {
        SaleState memory state = saleStates[party][saleId];

        initialDelegate = _beforeContribute(
            party,
            recipient,
            initialDelegate,
            state.gateKeeper,
            state.gateKeeperId,
            gateData
        );

        votingPower = _contribute(
            party,
            saleId,
            state,
            recipient,
            initialDelegate,
            msg.value.safeCastUint256ToUint96()
        );

        if (votingPower == 0) revert ZeroVotingPowerError();

        // Mint contributor a new party card.
        party.increaseTotalVotingPower(votingPower);
        party.mint(recipient, votingPower, initialDelegate);
    }

    function batchContribute(
        BatchContributeArgs memory args
    ) external payable returns (uint96[] memory votingPowers) {
        SaleState memory state = saleStates[args.party][args.saleId];

        // TODO: Check that _beforeContribute here works as expected
        args.delegate = _beforeContribute(
            args.party,
            msg.sender,
            args.delegate,
            state.gateKeeper,
            state.gateKeeperId,
            args.gateData
        );

        uint256 numOfContributions = args.values.length;
        uint96 totalValue;
        uint96 totalVotingPower;
        votingPowers = new uint96[](numOfContributions);
        for (uint256 i; i < numOfContributions; ++i) {
            uint96 value = args.values[i];
            // TODO: Check that _contribute works with this
            uint96 votingPower = votingPowers[i] = _contribute(
                args.party,
                args.saleId,
                state,
                msg.sender,
                args.delegate,
                value
            );

            if (votingPower == 0) revert ZeroVotingPowerError();

            totalValue += value;
            totalVotingPower += votingPower;
        }

        if (msg.value != totalValue) revert InvalidMessageValue();

        args.party.increaseTotalVotingPower(totalVotingPower);

        for (uint256 i; i < numOfContributions; ++i) {
            args.party.mint(msg.sender, votingPowers[i], args.delegate);
        }
    }

    // TODO: Check that _contribute works with this
    function batchContributeFor(
        BatchContributeForArgs memory args
    ) external payable returns (uint96[] memory votingPowers) {
        SaleState memory state = saleStates[args.party][args.saleId];

        // TODO: Check that _beforeContribute here works as expected
        args.initialDelegates = _beforeContribute(
            args.party,
            args.recipients,
            args.initialDelegates,
            state.gateKeeper,
            state.gateKeeperId,
            args.gateData
        );

        uint256 numOfContributions = args.values.length;
        uint96 totalValue;
        uint96 totalVotingPower;
        votingPowers = new uint96[](numOfContributions);
        for (uint256 i; i < numOfContributions; ++i) {
            uint96 value = args.values[i];
            // TODO: Check that _contribute works with this
            uint96 votingPower = votingPowers[i] = _contribute(
                args.party,
                args.saleId,
                state,
                args.recipients[i],
                args.initialDelegates[i],
                value
            );

            if (votingPower == 0) revert ZeroVotingPowerError();

            totalValue += value;
            totalVotingPower += votingPower;
        }

        if (msg.value != totalValue) revert InvalidMessageValue();

        args.party.increaseTotalVotingPower(totalVotingPower);

        for (uint256 i; i < numOfContributions; ++i) {
            args.party.mint(args.recipients[i], votingPowers[i], args.initialDelegates[i]);
        }
    }

    function finalize(Party party, uint256 saleId) external {
        SaleState memory state = saleStates[party][saleId];

        // Check that the sale is active.
        if (_isSaleActive(state.expiry, state.totalContributions, state.maxTotalContributions)) {
            // Allow host to finalize sale early.
            if (!party.isHost(msg.sender)) revert OnlyPartyHostError();

            saleStates[party][saleId].expiry = uint40(block.timestamp);

            emit Finalized(party, saleId);
        } else {
            // Already finalized.
            revert SaleInactiveError();
        }
    }

    function _beforeContribute(
        Party party,
        address contributor,
        address delegate,
        IGateKeeper gateKeeper,
        bytes12 gateKeeperId,
        bytes memory gateData
    ) private view returns (address) {
        address[] memory contributors = new address[](1);
        contributors[0] = contributor;
        address[] memory delegates = new address[](1);
        delegates[0] = delegate;

        delegates = _beforeContribute(
            party,
            contributors,
            delegates,
            gateKeeper,
            gateKeeperId,
            gateData
        );

        return delegates[0];
    }

    function _beforeContribute(
        Party party,
        address[] memory contributors,
        address[] memory delegates,
        IGateKeeper gateKeeper,
        bytes12 gateKeeperId,
        bytes memory gateData
    ) private view returns (address[] memory) {
        // Require a non-null delegate.
        for (uint256 i; i < delegates.length; ++i) {
            if (delegates[i] == address(0)) revert InvalidDelegateError();

            // Prevent changing another's delegate if already delegated.
            address oldDelegate = party.delegationsByVoter(contributors[i]);
            if (msg.sender != contributors[i] && oldDelegate != address(0)) {
                delegates[i] = oldDelegate;
            }
        }

        // Must not be blocked by gatekeeper.
        if (gateKeeper != IGateKeeper(address(0))) {
            if (!gateKeeper.isAllowed(msg.sender, gateKeeperId, gateData)) {
                revert NotAllowedByGateKeeperError(msg.sender, gateKeeper, gateKeeperId, gateData);
            }
        }

        return delegates;
    }

    function _contribute(
        Party party,
        uint256 saleId,
        SaleState memory state,
        address contributor,
        address delegate,
        uint96 amount
    ) private returns (uint96 votingPower) {
        // Check sale is active.
        uint96 totalContributions = state.totalContributions;
        uint96 maxTotalContributions = state.maxTotalContributions;
        if (!_isSaleActive(state.expiry, totalContributions, maxTotalContributions)) {
            revert SaleInactiveError();
        }

        emit Contributed(msg.sender, contributor, amount, delegate);

        // Check that the contribution amount is at or below the maximum.
        uint96 maxContribution = state.maxContribution;
        if (amount > maxContribution) {
            revert AboveMaximumContributionsError(amount, maxContribution);
        }

        uint96 newTotalContributions = totalContributions + amount;
        if (newTotalContributions >= maxTotalContributions) {
            // This occurs before refunding excess contribution to act as a
            // reentrancy guard.
            saleStates[party][saleId].totalContributions = maxTotalContributions;

            // Finalize the crowdfund.
            emit Finalized(party, saleId);

            // Refund excess contribution.
            uint96 refundAmount = newTotalContributions - maxTotalContributions;
            if (refundAmount > 0) {
                amount -= refundAmount;
                // Revert if the refund fails.
                payable(msg.sender).transferEth(refundAmount);
            }
        } else {
            saleStates[party][saleId].totalContributions = newTotalContributions;
        }

        // Check that the contribution amount is at or above the minimum. This
        // is done after `amount` is potentially reduced if refunding excess
        // contribution.
        uint96 minContribution = state.minContribution;
        if (amount < minContribution) {
            revert BelowMinimumContributionsError(amount, minContribution);
        }

        // Subtract fee from contribution amount if applicable.
        address payable fundingSplitRecipient = state.fundingSplitRecipient;
        uint16 fundingSplitBps = state.fundingSplitBps;
        if (fundingSplitRecipient != address(0) && fundingSplitBps > 0) {
            // Calculate funding split.
            uint96 fundingSplit = (amount * fundingSplitBps) / 1e4;

            // Transfer contribution to funding split recipient if applicable. Do not
            // revert if the transfer fails.
            fundingSplitRecipient.call{ value: fundingSplit }("");

            // Removes funding split from contribution amount in a way that
            // avoids rounding errors for very small contributions <1e4 wei.
            amount -= fundingSplit;
        }

        // Calculate voting power.
        votingPower = _convertContributionToVotingPower(amount, state.exchangeRateBps);
    }

    function convertContributionToVotingPower(
        Party party,
        uint256 saleId,
        uint96 contribution
    ) external view returns (uint96) {
        uint16 exchangeRateBps = saleStates[party][saleId].exchangeRateBps;
        return _convertContributionToVotingPower(contribution, exchangeRateBps);
    }

    function convertVotingPowerToContribution(
        Party party,
        uint256 saleId,
        uint96 votingPower
    ) external view returns (uint96) {
        uint16 exchangeRateBps = saleStates[party][saleId].exchangeRateBps;
        return _convertVotingPowerToContribution(votingPower, exchangeRateBps);
    }

    function _convertContributionToVotingPower(
        uint96 contribution,
        uint16 exchangeRateBps
    ) private pure returns (uint96) {
        return (contribution * exchangeRateBps) / 1e4;
    }

    function _convertVotingPowerToContribution(
        uint96 votingPower,
        uint16 exchangeRateBps
    ) private pure returns (uint96) {
        return (votingPower * 1e4) / exchangeRateBps;
    }

    function isSaleActive(Party party, uint256 saleId) external view returns (bool) {
        SaleState memory opts = saleStates[party][saleId];
        return _isSaleActive(opts.expiry, opts.totalContributions, opts.maxTotalContributions);
    }

    function _isSaleActive(
        uint40 expiry,
        uint96 totalContributions,
        uint96 maxTotalContributions
    ) private view returns (bool) {
        return block.timestamp < expiry && totalContributions < maxTotalContributions;
    }
}