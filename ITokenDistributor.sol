// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Interface for the token and ETH distributor contract.
interface ITokenDistributor {
    // ERC20s should be transferred in prior to calling.
    // The difference between the previous recorded balance of `token` will be
    // used to determine the distribution amount.
    // ETH (0xeee...) should be attached to the call.
    // Caller should be a PartyGovernance contract (implementing getVotingPowerAt()).
    // The voting power of the claimant at the block when the distribution
    // was created will determine the share of tokens that can be redeemed by
    // the claimant.
    function createDistribution(IERC20 token)
        external
        payable
        returns (uint256 distributionId);
    function claim(uint256 distributionId, IERC20 token)
        external
        returns (uint256 amountClaimed);
}