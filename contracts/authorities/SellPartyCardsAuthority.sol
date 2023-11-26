// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Party } from "contracts/party/Party.sol";
import { IGateKeeper } from "contracts/gatekeepers/IGateKeeper.sol";
import { LibSafeCast } from "contracts/utils/LibSafeCast.sol";
import { LibAddress } from "contracts/utils/LibAddress.sol";

contract SellPartyCardsAuthority {
    using LibSafeCast for uint96;
    using LibSafeCast for uint256;
    using LibAddress for address payable;

    struct FixedMembershipSaleOpts {
        // The price for each membership minted.
        uint96 pricePerMembership;
        // The voting power for each membership minted.
        uint96 votingPowerPerMembership;
        // The total number of memberships for sale.
        uint96 totalMembershipsForSale;
        // The split from each contribution to be received by the
        // fundingSplitRecipient, in basis points.
        uint16 fundingSplitBps;
        // The recipient of the funding split.
        address payable fundingSplitRecipient;
        // The duration of the sale.
        uint40 duration;
        // The gatekeeper contract.
        IGateKeeper gateKeeper;
        // The ID of the gatekeeper.
        bytes12 gateKeeperId;
    }

    struct FlexibleMembershipSaleOpts {
        // The minimum amount that can be contributed.
        uint96 minContribution;
        // The maximum amount that can be contributed.
        uint96 maxContribution;
        // The maximum total amount that can be contributed for the sale.
        uint96 maxTotalContributions;
        // The exchange rate from contribution amount to voting power, in basis
        // points. May be greater than 1e4 (100%).
        uint16 exchangeRateBps;
        // The split from each contribution to be received by the
        // fundingSplitRecipient, in basis points.
        uint16 fundingSplitBps;
        // The recipient of the funding split.
        address payable fundingSplitRecipient;
        // The duration of the sale.
        uint40 duration;
        // The gatekeeper contract.
        IGateKeeper gateKeeper;
        // The ID of the gatekeeper.
        bytes12 gateKeeperId;
    }

    struct SaleState {
        // The minimum amount that can be contributed.
        uint96 minContribution;
        // The maximum amount that can be contributed.
        uint96 maxContribution;
        // The total amount that has been contributed.
        uint96 totalContributions;
        // The maximum total amount that can be contributed for the sale.
        uint96 maxTotalContributions;
        // The exchange rate from contribution amount to voting power, in basis
        // points. May be greater than 1e4 (100%).
        uint16 exchangeRateBps;
        // The split from each contribution to be received by the
        // fundingSplitRecipient, in basis points.
        uint16 fundingSplitBps;
        // The recipient of the funding split.
        address payable fundingSplitRecipient;
        // The time at which the sale expires.
        uint40 expiry;
        // The gatekeeper contract.
        IGateKeeper gateKeeper;
        // The ID of the gatekeeper.
        bytes12 gateKeeperId;
    }

    /// @notice The ID of the last sale for each Party.
    mapping(Party party => uint256 lastId) public lastSaleId;
    // Details of each sale.
    mapping(Party party => mapping(uint256 id => SaleState opts)) private _saleStates;

    event CreatedSale(Party indexed party, uint256 indexed saleId, SaleState state);
    event Finalized(Party indexed party, uint256 indexed saleId);
    event MintedFromSale(
        Party indexed party,
        uint256 indexed saledId,
        uint256 indexed tokenId,
        address sender,
        address contributor,
        uint96 contribution,
        address initialDelegate
    );

    error NotAuthorizedError();
    error MinGreaterThanMaxError(uint96 minContribution, uint96 maxContribution);
    error ZeroMaxTotalContributionsError();
    error ZeroExchangeRateBpsError();
    error InvalidBpsError(uint16 fundingSplitBps);
    error ZeroVotingPowerError();
    error InvalidMessageValue();
    error OnlyPartyHostError();
    error SaleInactiveError();
    error InvalidInitialDelegateError();
    error NotAllowedByGateKeeperError(
        address sender,
        IGateKeeper gateKeeper,
        bytes12 gateKeeperId,
        bytes gateData
    );
    error OutOfBoundsContributionsError(uint96 amount, uint96 bound);

    /// @notice Create a new fixed membership sale.
    /// @param opts Options used to initialize the sale.
    /// @return saleId The ID of the sale created.
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

    /// @notice Create a new flexible membership sale.
    /// @param opts Options used to initialize the sale.
    /// @return saleId The ID of the sale created.
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

        // Ensure that this contract is an authority in the Party.
        if (!party.isAuthority(address(this))) revert NotAuthorizedError();

        // Create sale.
        saleId = ++lastSaleId[party];
        _saleStates[party][saleId] = state;

        emit CreatedSale(party, saleId, state);
    }

    /// @notice Contribute to a sale and receive a minted NFT from the Party.
    /// @param party The Party to contribute to.
    /// @param saleId The ID of the sale to contribute to.
    /// @param initialDelegate The delegate to use for the contribution. This will be
    ///                 ignored if caller has already set a delegate.
    /// @param gateData Data to pass to the gatekeeper.
    /// @return votingPower The voting power received from the contribution.
    function contribute(
        Party party,
        uint256 saleId,
        address initialDelegate,
        bytes calldata gateData
    ) external payable returns (uint96 votingPower) {
        uint96 contribution = msg.value.safeCastUint256ToUint96();

        (votingPower, contribution) = _contribute(party, saleId, contribution, gateData);

        _mint(party, saleId, msg.sender, contribution, votingPower, initialDelegate);
    }

    /// @notice Contribute to a sale and receive a minted NFT from the Party.
    /// @param party The Party to contribute to.
    /// @param saleId The ID of the sale to contribute to.
    /// @param recipient The recipient of the minted NFT.
    /// @param initialDelegate The delegate to use for the contribution. This will be
    ///                 ignored if recipient has already set a delegate.
    /// @param gateData Data to pass to the gatekeeper.
    /// @return votingPower The voting power received from the contribution.
    function contributeFor(
        Party party,
        uint256 saleId,
        address recipient,
        address initialDelegate,
        bytes calldata gateData
    ) external payable returns (uint96 votingPower) {
        uint96 contribution = msg.value.safeCastUint256ToUint96();

        (votingPower, contribution) = _contribute(party, saleId, contribution, gateData);

        _mint(party, saleId, recipient, contribution, votingPower, initialDelegate);
    }

    /// @notice Contribute to a sale and receive a minted NFT from the Party.
    /// @param party The Party to contribute to.
    /// @param saleId The ID of the sale to contribute to.
    /// @param initialDelegate The delegate to use for all contributions. This will be
    ///                 ignored if caller has already set a delegate.
    /// @param contributions The amounts of each contribution.
    /// @param gateData Data to pass to the gatekeeper.
    /// @return votingPowers The voting powers received from each contribution.
    function batchContribute(
        Party party,
        uint256 saleId,
        address initialDelegate,
        uint96[] memory contributions,
        bytes calldata gateData
    ) external payable returns (uint96[] memory votingPowers) {
        (votingPowers, contributions) = _batchContribute(party, saleId, contributions, gateData);

        for (uint256 i; i < contributions.length; ++i) {
            _mint(party, saleId, msg.sender, contributions[i], votingPowers[i], initialDelegate);
        }
    }

    /// @notice Contribute to a sale and receive a minted NFT from the Party.
    /// @param party The Party to contribute to.
    /// @param saleId The ID of the sale to contribute to.
    /// @param recipients The recipients of the minted NFTs.
    /// @param initialDelegates The delegates to use for each contribution. This will be
    ///                  ignored if recipient has already set a delegate.
    /// @param contributions The amounts of each contribution.
    /// @param gateData Data to pass to the gatekeeper.
    /// @return votingPowers The voting powers received from each contribution.
    function batchContributeFor(
        Party party,
        uint256 saleId,
        address[] calldata recipients,
        address[] calldata initialDelegates,
        uint96[] memory contributions,
        bytes calldata gateData
    ) external payable returns (uint96[] memory votingPowers) {
        (votingPowers, contributions) = _batchContribute(party, saleId, contributions, gateData);

        for (uint256 i; i < contributions.length; ++i) {
            _mint(
                party,
                saleId,
                recipients[i],
                contributions[i],
                votingPowers[i],
                initialDelegates[i]
            );
        }
    }

    /// @notice Finalize a sale early before the expiry as a host.
    /// @param party The Party to finalize the sale for.
    /// @param saleId The ID of the sale to finalize.
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

    /// @notice Get the details of a fixed membership sale.
    /// @param party The Party that created the sale.
    /// @param saleId The ID of the sale.
    /// @return pricePerMembership The price for each membership minted.
    /// @return votingPowerPerMembership The voting power for each membership
    ///                                  minted.
    /// @return totalContributions The total amount that has been contributed.
    /// @return totalMembershipsForSale The total number of memberships for
    ///                                 sale.
    /// @return fundingSplitBps The split from each contribution to be received
    ///                         by the fundingSplitRecipient, in basis points.
    /// @return fundingSplitRecipient The recipient of the funding split.
    /// @return expiry The time at which the sale expires.
    /// @return gateKeeper The gatekeeper contract.
    /// @return gateKeeperId The ID of the gatekeeper.
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

    /// @notice Get the details of a flexible membership sale.
    /// @param party The Party that created the sale.
    /// @param saleId The ID of the sale.
    /// @return minContribution The minimum amount that can be contributed.
    /// @return maxContribution The maximum amount that can be contributed.
    /// @return totalContributions The total amount that has been contributed.
    /// @return maxTotalContributions The maximum total amount that can be
    ///                               contributed for the sale.
    /// @return exchangeRateBps The exchange rate from contribution amount to
    ///                         voting power, in basis points.
    /// @return fundingSplitBps The split from each contribution to be received
    ///                         by the fundingSplitRecipient, in basis points.
    /// @return fundingSplitRecipient The recipient of the funding split.
    /// @return expiry The time at which the sale expires.
    /// @return gateKeeper The gatekeeper contract.
    /// @return gateKeeperId The ID of the gatekeeper.
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

    /// @notice Check if a sale is active.
    /// @param party The Party that created the sale.
    /// @param saleId The ID of the sale.
    /// @return status Whether the sale is active or not.
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

    /// @notice Convert a contribution amount to voting power.
    /// @param party The Party that created the sale.
    /// @param saleId The ID of the sale.
    /// @param contribution The contribution amount.
    /// @return votingPower The voting power amount that would be received from
    ///                     the contribution.
    function convertContributionToVotingPower(
        Party party,
        uint256 saleId,
        uint96 contribution
    ) external view returns (uint96) {
        uint16 exchangeRateBps = _saleStates[party][saleId].exchangeRateBps;
        return _convertContributionToVotingPower(contribution, exchangeRateBps);
    }

    /// @notice Convert a voting power amount to a contribution amount.
    /// @param party The Party that created the sale.
    /// @param saleId The ID of the sale.
    /// @param votingPower The voting power amount.
    /// @return contribution The contribution amount that would be required to
    ///                      receive the voting power.
    function convertVotingPowerToContribution(
        Party party,
        uint256 saleId,
        uint96 votingPower
    ) external view returns (uint96) {
        uint16 exchangeRateBps = _saleStates[party][saleId].exchangeRateBps;
        return _convertVotingPowerToContribution(votingPower, exchangeRateBps);
    }

    function _contribute(
        Party party,
        uint256 saleId,
        uint96 contribution,
        bytes calldata gateData
    ) private returns (uint96 votingPower, uint96 /* contribution */) {
        SaleState memory state = _validateContribution(party, saleId, gateData);

        (votingPower, contribution, ) = _processContribution(party, saleId, state, contribution);

        // Transfer amount due to the Party. Revert if the transfer fails.
        payable(address(party)).transferEth(address(this).balance);

        // Mint contributor a new party card.
        party.increaseTotalVotingPower(votingPower);

        return (votingPower, contribution);
    }

    function _batchContribute(
        Party party,
        uint256 saleId,
        uint96[] memory contributions,
        bytes calldata gateData
    ) private returns (uint96[] memory votingPowers, uint96[] memory /* contributions */) {
        SaleState memory state = _validateContribution(party, saleId, gateData);

        uint256 numOfContributions = contributions.length;
        uint96 totalValue;
        uint96 totalVotingPower;
        votingPowers = new uint96[](numOfContributions);
        for (uint256 i; i < numOfContributions; ++i) {
            uint96 contribution = contributions[i];
            uint96 votingPower;

            (votingPower, contributions[i], state.totalContributions) = _processContribution(
                party,
                saleId,
                state,
                contribution
            );

            votingPowers[i] = votingPower;

            totalValue += contribution;
            totalVotingPower += votingPower;
        }

        if (msg.value != totalValue) revert InvalidMessageValue();

        // Transfer amount due to the Party. Revert if the transfer fails.
        payable(address(party)).transferEth(address(this).balance);

        party.increaseTotalVotingPower(totalVotingPower);

        return (votingPowers, contributions);
    }

    /// @dev `totalContributions` is updated and returned for use in
    ///      `batchContribute` and `batchContributeFor`.
    function _processContribution(
        Party party,
        uint256 saleId,
        SaleState memory state,
        uint96 amount
    ) private returns (uint96 votingPower, uint96 contribution, uint96 totalContributions) {
        totalContributions = state.totalContributions;
        uint96 maxTotalContributions = state.maxTotalContributions;

        // Check sale is active.
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

        uint96 minContribution = state.minContribution;
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

            // Check if not enough room for another contribution. If so, sale is
            // finalized.
            if (minContribution > maxTotalContributions - newTotalContributions) {
                emit Finalized(party, saleId);
            }
        }

        // Check that the contribution amount is at or above the minimum. This
        // is done after `amount` is potentially reduced if refunding excess
        // contribution.
        if (amount < minContribution) {
            revert OutOfBoundsContributionsError(amount, minContribution);
        }

        // Return actual contribution amount used (before split is applied).
        // Will be emitted in MintedFromSale event.
        contribution = amount;

        // Subtract split from contribution amount if applicable.
        address payable fundingSplitRecipient = state.fundingSplitRecipient;
        uint16 fundingSplitBps = state.fundingSplitBps;
        if (fundingSplitRecipient != address(0) && fundingSplitBps > 0) {
            // Calculate funding split in a way that avoids rounding errors for
            // very small contributions <1e4 wei.
            uint96 fundingSplit = (amount * fundingSplitBps) / 1e4;

            amount -= fundingSplit;

            // Transfer contribution to funding split recipient if applicable. Do not
            // revert if the transfer fails.
            fundingSplitRecipient.call{ value: fundingSplit }("");
        }

        // Calculate voting power.
        votingPower = _convertContributionToVotingPower(amount, state.exchangeRateBps);

        if (votingPower == 0) revert ZeroVotingPowerError();
    }

    function _validateContribution(
        Party party,
        uint256 saleId,
        bytes calldata gateData
    ) private view returns (SaleState memory state) {
        state = _saleStates[party][saleId];

        // Must not be blocked by gatekeeper.
        IGateKeeper gateKeeper = state.gateKeeper;
        bytes12 gateKeeperId = state.gateKeeperId;
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
        uint96 contribution,
        uint96 votingPower,
        address initialDelegate
    ) private returns (uint256 tokenId) {
        tokenId = party.mint(recipient, votingPower, initialDelegate);
        emit MintedFromSale(
            party,
            saleId,
            tokenId,
            msg.sender,
            recipient,
            contribution,
            initialDelegate
        );
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

    function _isSaleActive(
        uint40 expiry,
        uint96 totalContributions,
        uint96 minContribution,
        uint96 maxTotalContributions
    ) private view returns (bool) {
        return
            // Check this condition first because it is more likely to change
            // within the same call. Expiry more likely to remain constant.
            maxTotalContributions - totalContributions >= minContribution &&
            block.timestamp < expiry;
    }
}
