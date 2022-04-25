// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Interface for the token and ETH distributor contract.
interface ITokenDistributor {
    // ERC20s should be transferred in prior to calling.
    // The difference between the previous recorded balance of `token` will be
    // used to determine the distribution amount.
    // ETH (0xeee...) should be attached to the call.
    // Caller should be an instance of the PartyGovernanceNFT contract contract.
    function createDistribution(IERC20 token)
        external
        payable
        returns (uint256 distributionId);
    // Claim a distribution based on a PartyGovernanceNFT.
    function claim(
        uint256 distributionId,
        PartyGovernanceNFT governanceToken,
        uint256 governanceTokenId
    )
        external
        returns (uint256 amountClaimed);
}
