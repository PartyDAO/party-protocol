// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { InitialETHCrowdfund } from "./InitialETHCrowdfund.sol";
import { Party } from "../party/Party.sol";
import { MetadataProvider } from "../renderers/MetadataProvider.sol";
import { IGlobals } from "../globals/IGlobals.sol";
import { IERC20Creator, TokenConfiguration } from "../utils/IERC20Creator.sol";

/// @notice A crowdfund for launching ERC20 tokens.
///         Unlike other crowdfunds that are started for the purpose of
///         acquiring NFT(s), this crowdfund bootstraps an ERC20 token
///         and sends a share of the total supply to the new party.
contract ERC20LaunchCrowdfund is InitialETHCrowdfund {
    struct ERC20LaunchOptions {
        // The name of the ERC20 token launched.
        string name;
        // The symbol of the ERC20 token launched.
        string symbol;
        // An arbitrary address to receive ERC20 tokens.
        address recipient;
        // The total supply to mint for the ERC20 token.
        uint256 totalSupply;
        // The number of tokens to distribute to the party.
        uint256 numTokensForDistribution;
        // The number of tokens to send to an arbitrary recipient.
        uint256 numTokensForRecipient;
        // The number of tokens to use for the Uniswap LP pair.
        uint256 numTokensForLP;
    }

    error InvalidTokenDistribution();

    IERC20Creator public immutable ERC20_CREATOR;

    ERC20LaunchOptions public tokenOpts;

    constructor(IGlobals globals, IERC20Creator erc20Creator) InitialETHCrowdfund(globals) {
        ERC20_CREATOR = erc20Creator;
    }

    /// @notice Initializer to be called prior to using the contract.
    /// @param crowdfundOpts Options to initialize the crowdfund with.
    /// @param partyOpts Options to initialize the party with.
    /// @param customMetadataProvider Optional provider to use for the party for
    ///                               rendering custom metadata.
    /// @param customMetadata Optional custom metadata to use for the party.
    function initialize(
        InitialETHCrowdfundOptions memory crowdfundOpts,
        ETHPartyOptions memory partyOpts,
        ERC20LaunchOptions memory _tokenOpts,
        MetadataProvider customMetadataProvider,
        bytes memory customMetadata
    ) external payable {
        if (
            _tokenOpts.numTokensForDistribution +
                _tokenOpts.numTokensForRecipient +
                _tokenOpts.numTokensForLP !=
            _tokenOpts.totalSupply ||
            _tokenOpts.totalSupply > type(uint112).max
        ) {
            revert InvalidTokenDistribution();
        }

        tokenOpts = _tokenOpts;

        InitialETHCrowdfund.initialize(
            crowdfundOpts,
            partyOpts,
            customMetadataProvider,
            customMetadata
        );
    }

    function _finalize(uint96 totalContributions_) internal override {
        Party _party = party;

        // Finalize the crowdfund.
        delete expiry;

        // Transfer funding split to recipient if applicable.
        uint16 fundingSplitBps_ = fundingSplitBps;
        if (fundingSplitBps_ > 0) {
            // Assuming fundingSplitBps_ <= 1e4, this cannot overflow uint96
            totalContributions_ -= uint96((uint256(totalContributions_) * fundingSplitBps_) / 1e4);
        }

        // Update the party's total voting power.
        uint96 newVotingPower = _calculateContributionToVotingPower(totalContributions_);
        _party.increaseTotalVotingPower(newVotingPower);

        emit Finalized();

        ERC20LaunchOptions memory _tokenOpts = tokenOpts;

        // Create the ERC20 token.
        ERC20_CREATOR.createToken{ value: totalContributions_ }(
            address(_party),
            _tokenOpts.name,
            _tokenOpts.symbol,
            TokenConfiguration({
                totalSupply: _tokenOpts.totalSupply,
                numTokensForDistribution: _tokenOpts.numTokensForDistribution,
                numTokensForRecipient: _tokenOpts.numTokensForRecipient,
                numTokensForLP: _tokenOpts.numTokensForLP
            }),
            _tokenOpts.recipient
        );
    }
}
