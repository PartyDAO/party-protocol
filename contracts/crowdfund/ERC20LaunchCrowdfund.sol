// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { InitialETHCrowdfund } from "./InitialETHCrowdfund.sol";
import { Party } from "../party/Party.sol";
import { MetadataProvider } from "../renderers/MetadataProvider.sol";
import { IGlobals } from "../globals/IGlobals.sol";
import { IERC20Creator, TokenConfiguration, ERC20 } from "../utils/IERC20Creator.sol";

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
    error TokenAlreadyLaunched();

    address public constant PARTY_ADDRESS_KEY =
        address(uint160(uint256(keccak256(abi.encode("party address")))));
    IERC20Creator public immutable ERC20_CREATOR;

    ERC20LaunchOptions public tokenOpts;

    bool public isTokenLaunched;

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
        uint16 feeBasisPoints = 5e3; // Max possible fee
        uint256 minTotalSpendableEth = ((((uint256(crowdfundOpts.minTotalContributions) *
            (1e4 - crowdfundOpts.fundingSplitBps)) / 1e4) * (1e4 - feeBasisPoints)) / 1e4);
        uint256 numTokensForLP = uint256(_tokenOpts.numTokensForLP);

        if (
            _tokenOpts.numTokensForDistribution +
                _tokenOpts.numTokensForRecipient +
                _tokenOpts.numTokensForLP !=
            _tokenOpts.totalSupply ||
            _tokenOpts.totalSupply > type(uint112).max ||
            _tokenOpts.numTokensForLP < 1e4 ||
            crowdfundOpts.fundingSplitBps > 5e3 ||
            crowdfundOpts.minTotalContributions < 1e4 ||
            crowdfundOpts.maxTotalContributions >= numTokensForLP * 1e18 ||
            _tokenOpts.numTokensForLP >= minTotalSpendableEth * 1e18
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

    /// @notice Launch the ERC20 token for the Party.
    function launchToken() public returns (ERC20 token) {
        if (isTokenLaunched) revert TokenAlreadyLaunched();

        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        if (lc != CrowdfundLifecycle.Finalized) revert WrongLifecycleError(lc);

        isTokenLaunched = true;

        // Update the party's total voting power
        uint96 totalContributions_ = totalContributions;

        uint16 fundingSplitBps_ = fundingSplitBps;
        if (fundingSplitBps_ > 0) {
            // Assuming fundingSplitBps_ <= 1e4, this cannot overflow uint96
            totalContributions_ -= uint96((uint256(totalContributions_) * fundingSplitBps_) / 1e4);
        }

        address tokenRecipient = tokenOpts.recipient;
        if (tokenRecipient == PARTY_ADDRESS_KEY) {
            tokenRecipient = address(party);
        }

        // Create the ERC20 token.
        ERC20LaunchOptions memory _tokenOpts = tokenOpts;
        token = ERC20_CREATOR.createToken{ value: totalContributions_ }(
            address(party),
            _tokenOpts.name,
            _tokenOpts.symbol,
            TokenConfiguration({
                totalSupply: _tokenOpts.totalSupply,
                numTokensForDistribution: _tokenOpts.numTokensForDistribution,
                numTokensForRecipient: _tokenOpts.numTokensForRecipient,
                numTokensForLP: _tokenOpts.numTokensForLP
            }),
            tokenRecipient
        );
    }

    /// @notice Finalize the crowdfund and launch the ERC20 token.
    function finalize() public override {
        super.finalize();
        launchToken();
    }

    function _finalize(uint96 totalContributions_) internal override {
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
        party.increaseTotalVotingPower(newVotingPower);

        emit Finalized();
    }
}
