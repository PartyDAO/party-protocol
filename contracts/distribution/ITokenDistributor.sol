// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Interface for the token and ETH distributor contract.
interface ITokenDistributor {
    event DistributionCreated(
        uint256 distributionId,
        ITokenDistributorParty party,
        IERC20 token,
        uint256 supply
    );

    // ERC20s should be transferred in prior to calling.
    // The difference between the previous recorded balance of `token` will be
    // used to determine the distribution amount.
    // ETH (0xeee...) should be attached to the call.
    // Caller should implement ITokenDistributorParty instance of the PartyGovernanceNFT contract contract.
    function createDistribution(IERC20 token)
        external
        payable
        returns (uint256 distributionId);

    // Claim a distribution as a party member based on the weight of a
    // PartyGovernanceNFT owned by the caller.
    function claim(
        uint256 distributionId,
        ITokenDistributorParty party,
        IERC20 token,
        uint256 supply,
        uint256 governanceTokenId,
        address recipient
    )
        external
        returns (uint256 amountClaimed);

    // Claim PartyDAO's split of a distribution.
    function partyDaoClaim(
        uint256 distributionId,
        ITokenDistributorParty party,
        IERC20 token,
        uint256 supply,
        address recipient
    )
        external
        returns (uint256 amountClaimed);
}
