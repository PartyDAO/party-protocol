// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "contracts/party/Party.sol";
import "contracts/gatekeepers/IGateKeeper.sol";

// TODO: Use named imports
// TODO: Update contribution router to support batch contributions
// TODO: Document that exchangeRateBps may be greater than 1e4 (100%)
// TODO: Add natspec

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
        address[] delegates;
        uint96[] values;
        bytes gateData;
    }

    mapping(Party party => uint256 lastId) public lastSaleId;
    mapping(Party party => mapping(uint256 id => SaleState opts)) private _saleStates;

    event CreatedSale(Party indexed party, uint256 indexed saleId, SaleState state);
    event Finalized(Party indexed party, uint256 indexed saleId);
    event MintedFromSale(
        Party indexed party,
        uint256 indexed saledId,
        uint256 indexed tokenId,
        address sender,
        address contributor,
        uint96 amount,
        address delegate
    );

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
    error OutOfBoundsContributionsError(uint96 amount, uint96 bound);

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
        _saleStates[party][saleId] = state;

        emit CreatedSale(party, saleId, state);
    }

    function contribute(
        Party party,
        uint256 saleId,
        address delegate,
        bytes calldata gateData
    ) external payable returns (uint96 votingPower) {
        SaleState memory state = _saleStates[party][saleId];

        _assertIsAllowedByGatekeeper(state.gateKeeper, state.gateKeeperId, gateData);

        // TODO: Check that _contribute here works as expected
        (votingPower, ) = _contribute(
            party,
            saleId,
            state,
            msg.sender,
            delegate,
            uint96(msg.value)
        );

        if (votingPower == 0) revert ZeroVotingPowerError();

        // Revert if the transfer fails.
        payable(address(party)).transferEth(address(this).balance);

        // Mint contributor a new party card.
        party.increaseTotalVotingPower(votingPower);
        _mint(party, saleId, msg.sender, votingPower, delegate);
    }

    function contributeFor(
        Party party,
        uint256 saleId,
        address recipient,
        address delegate,
        bytes calldata gateData
    ) external payable returns (uint96 votingPower) {
        SaleState memory state = _saleStates[party][saleId];

        _assertIsAllowedByGatekeeper(state.gateKeeper, state.gateKeeperId, gateData);

        (votingPower, ) = _contribute(
            party,
            saleId,
            state,
            recipient,
            delegate,
            msg.value.safeCastUint256ToUint96()
        );

        if (votingPower == 0) revert ZeroVotingPowerError();

        // Revert if the transfer fails.
        payable(address(party)).transferEth(address(this).balance);

        // Mint contributor a new party card.
        party.increaseTotalVotingPower(votingPower);
        _mint(party, saleId, recipient, votingPower, delegate);
    }

    function batchContribute(
        BatchContributeArgs memory args
    ) external payable returns (uint96[] memory votingPowers) {
        SaleState memory state = _saleStates[args.party][args.saleId];

        _assertIsAllowedByGatekeeper(state.gateKeeper, state.gateKeeperId, args.gateData);

        uint256 numOfContributions = args.values.length;
        uint96 totalValue;
        uint96 totalVotingPower;
        votingPowers = new uint96[](numOfContributions);
        for (uint256 i; i < numOfContributions; ++i) {
            uint96 value = args.values[i];
            // TODO: Check that _contribute works with this
            uint96 votingPower;
            (votingPower, state.totalContributions) = _contribute(
                args.party,
                args.saleId,
                state,
                msg.sender,
                args.delegate,
                value
            );

            if (votingPower == 0) revert ZeroVotingPowerError();

            votingPowers[i] = votingPower;

            totalValue += value;
            totalVotingPower += votingPower;
        }

        if (msg.value != totalValue) revert InvalidMessageValue();

        // Revert if the transfer fails.
        payable(address(args.party)).transferEth(address(this).balance);

        args.party.increaseTotalVotingPower(totalVotingPower);

        for (uint256 i; i < numOfContributions; ++i) {
            _mint(args.party, args.saleId, msg.sender, votingPowers[i], args.delegate);
        }
    }

    // TODO: Check that _contribute works with this
    function batchContributeFor(
        BatchContributeForArgs memory args
    ) external payable returns (uint96[] memory votingPowers) {
        SaleState memory state = _saleStates[args.party][args.saleId];

        _assertIsAllowedByGatekeeper(state.gateKeeper, state.gateKeeperId, args.gateData);

        uint256 numOfContributions = args.values.length;
        uint96 totalValue;
        uint96 totalVotingPower;
        votingPowers = new uint96[](numOfContributions);
        for (uint256 i; i < numOfContributions; ++i) {
            uint96 value = args.values[i];
            // TODO: Check that _contribute works with this
            uint96 votingPower;
            (votingPower, state.totalContributions) = _contribute(
                args.party,
                args.saleId,
                state,
                args.recipients[i],
                args.delegates[i],
                value
            );

            if (votingPower == 0) revert ZeroVotingPowerError();

            votingPowers[i] = votingPower;

            totalValue += value;
            totalVotingPower += votingPower;
        }

        if (msg.value != totalValue) revert InvalidMessageValue();

        // Revert if the transfer fails.
        payable(address(args.party)).transferEth(address(this).balance);

        args.party.increaseTotalVotingPower(totalVotingPower);

        for (uint256 i; i < numOfContributions; ++i) {
            _mint(args.party, args.saleId, args.recipients[i], votingPowers[i], args.delegates[i]);
        }
    }

    function finalize(Party party, uint256 saleId) external {
        SaleState memory state = _saleStates[party][saleId];

        // Check that the sale is active.
        if (
            _isSaleActive(
                state.expiry,
                state.totalContributions,
                state.minContribution,
                state.maxTotalContributions
            )
        ) {
            // Allow host to finalize sale early.
            if (!party.isHost(msg.sender)) revert OnlyPartyHostError();

            _saleStates[party][saleId].expiry = uint40(block.timestamp);

            emit Finalized(party, saleId);
        } else {
            // Already finalized.
            revert SaleInactiveError();
        }
    }

    /// @dev `totalContributions` is updated and returned for use in
    ///      `batchContribute` and `batchContributeFor`.
    function _contribute(
        Party party,
        uint256 saleId,
        SaleState memory state,
        address contributor,
        address delegate,
        uint96 amount
    ) private returns (uint96 votingPower, uint96 totalContributions) {
        // Check sale is active.
        totalContributions = state.totalContributions;
        uint96 maxTotalContributions = state.maxTotalContributions;
        if (
            !_isSaleActive(
                state.expiry,
                totalContributions,
                state.minContribution,
                maxTotalContributions
            )
        ) {
            revert SaleInactiveError();
        }

        // Check that the contribution amount is at or below the maximum.
        uint96 maxContribution = state.maxContribution;
        if (amount > maxContribution) {
            revert OutOfBoundsContributionsError(amount, maxContribution);
        }

        uint96 newTotalContributions = totalContributions + amount;
        if (newTotalContributions >= maxTotalContributions) {
            // This occurs before refunding excess contribution to act as a
            // reentrancy guard.
            _saleStates[party][saleId]
                .totalContributions = totalContributions = maxTotalContributions;

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
            _saleStates[party][saleId]
                .totalContributions = totalContributions = newTotalContributions;
        }

        // Check that the contribution amount is at or above the minimum. This
        // is done after `amount` is potentially reduced if refunding excess
        // contribution.
        uint96 minContribution = state.minContribution;
        if (amount < minContribution) {
            revert OutOfBoundsContributionsError(amount, minContribution);
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

    function _assertIsAllowedByGatekeeper(
        IGateKeeper gateKeeper,
        bytes12 gateKeeperId,
        bytes memory gateData
    ) private view {
        // Must not be blocked by gatekeeper.
        if (gateKeeper != IGateKeeper(address(0))) {
            if (!gateKeeper.isAllowed(msg.sender, gateKeeperId, gateData)) {
                revert NotAllowedByGateKeeperError(msg.sender, gateKeeper, gateKeeperId, gateData);
            }
        }
    }

    function _mint(
        Party party,
        uint256 saleId,
        address recipient,
        uint96 votingPower,
        address delegate
    ) private returns (uint256 tokenId) {
        tokenId = party.mint(recipient, votingPower, delegate);
        emit MintedFromSale(party, saleId, tokenId, msg.sender, recipient, votingPower, delegate);
    }

    function convertContributionToVotingPower(
        Party party,
        uint256 saleId,
        uint96 contribution
    ) external view returns (uint96) {
        uint16 exchangeRateBps = _saleStates[party][saleId].exchangeRateBps;
        return _convertContributionToVotingPower(contribution, exchangeRateBps);
    }

    function convertVotingPowerToContribution(
        Party party,
        uint256 saleId,
        uint96 votingPower
    ) external view returns (uint96) {
        uint16 exchangeRateBps = _saleStates[party][saleId].exchangeRateBps;
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

    function getFixedMembershipSaleInfo(
        Party party,
        uint256 saleId
    )
        external
        view
        returns (
            uint96 pricePerMembership,
            uint96 votingPowerPerMembership,
            uint96 totalContributions,
            uint96 totalMembershipsForSale,
            uint16 fundingSplitBps,
            address payable fundingSplitRecipient,
            uint40 expiry,
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId
        )
    {
        SaleState memory opts = _saleStates[party][saleId];
        pricePerMembership = opts.minContribution;
        votingPowerPerMembership = _convertContributionToVotingPower(
            pricePerMembership,
            opts.exchangeRateBps
        );
        totalContributions = opts.totalContributions;
        totalMembershipsForSale = opts.maxTotalContributions / opts.minContribution;
        fundingSplitBps = opts.fundingSplitBps;
        fundingSplitRecipient = opts.fundingSplitRecipient;
        expiry = opts.expiry;
        gateKeeper = opts.gateKeeper;
        gateKeeperId = opts.gateKeeperId;
    }

    function getFlexibleMembershipSaleInfo(
        Party party,
        uint256 saleId
    )
        external
        view
        returns (
            uint96 minContribution,
            uint96 maxContribution,
            uint96 totalContributions,
            uint96 maxTotalContributions,
            uint16 exchangeRateBps,
            uint16 fundingSplitBps,
            address payable fundingSplitRecipient,
            uint40 expiry,
            IGateKeeper gateKeeper,
            bytes12 gateKeeperId
        )
    {
        SaleState memory opts = _saleStates[party][saleId];
        minContribution = opts.minContribution;
        maxContribution = opts.maxContribution;
        totalContributions = opts.totalContributions;
        maxTotalContributions = opts.maxTotalContributions;
        exchangeRateBps = opts.exchangeRateBps;
        fundingSplitBps = opts.fundingSplitBps;
        fundingSplitRecipient = opts.fundingSplitRecipient;
        expiry = opts.expiry;
        gateKeeper = opts.gateKeeper;
        gateKeeperId = opts.gateKeeperId;
    }

    function isSaleActive(Party party, uint256 saleId) external view returns (bool) {
        SaleState memory opts = _saleStates[party][saleId];
        return
            _isSaleActive(
                opts.expiry,
                opts.totalContributions,
                opts.minContribution,
                opts.maxTotalContributions
            );
    }

    function _isSaleActive(
        uint40 expiry,
        uint96 totalContributions,
        uint96 minContribution,
        uint96 maxTotalContributions
    ) private view returns (bool) {
        return
            block.timestamp < expiry &&
            maxTotalContributions - totalContributions >= minContribution;
    }
}
