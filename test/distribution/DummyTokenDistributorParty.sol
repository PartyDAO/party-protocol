// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

contract DummyTokenDistributorParty {
    struct GovernanceValues {
        uint40 voteDuration;
        uint40 executionDelay;
        uint16 passThresholdBps;
        uint96 totalVotingPower;
        uint8 numHosts;
    }

    GovernanceValues _governanceValues;
    mapping(uint256 => address) _owners;
    mapping(uint256 => uint256) _shares; // token id -> share amount

    constructor() {
        _governanceValues.voteDuration = 100;
        _governanceValues.executionDelay = 100;
        _governanceValues.passThresholdBps = 100;
        _governanceValues.totalVotingPower = 100;
    }

    function setOwner(address owner, uint256 tokenId) public {
        _owners[tokenId] = owner;
    }

    function setShare(uint256 tokenId, uint256 shareAmount) public {
        _shares[tokenId] = shareAmount;
    }

    function setTotalShares(uint96 totalShares) external {
        _governanceValues.totalVotingPower = totalShares;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address foundOwner = _owners[tokenId];
        if (foundOwner == address(0)) {
            revert();
        }
        return foundOwner;
    }

    function getDistributionShareOf(uint256 tokenId) external view returns (uint256) {
        return _shares[tokenId];
    }

    function getGovernanceValues() external view returns (GovernanceValues memory) {
        return _governanceValues;
    }

    function tokenCount() external view virtual returns (uint96) {
        return type(uint96).max;
    }
}
