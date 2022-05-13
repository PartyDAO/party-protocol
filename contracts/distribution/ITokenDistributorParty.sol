// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

// Interface the caller of `ITokenDistributor.createDistribution()` must implement.
interface ITokenDistributorParty {
    // Return the owner of a token.
    function ownerOf(uint256 tokenId) external view returns (address);
    // Return the distribution share of a token. Denominated fractions of 1e18.
    // I.e., 1e18 = 100%.
    function getDistributionShareOf(uint256 tokenId) external view returns (uint256);
}
