// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { Party, PartyGovernance, PartyGovernanceNFT } from "../../contracts/party/Party.sol";
import { ProposalExecutionEngine } from "../../contracts/proposals/ProposalExecutionEngine.sol";
import { BondingCurveAuthority } from "../../contracts/authorities/BondingCurveAuthority.sol";
import { ArbitraryCallsProposal } from "../../contracts/proposals/ArbitraryCallsProposal.sol";

contract BondingCurveAuthorityTest is SetupPartyHelper {
    constructor() SetupPartyHelper(false) {}

    MockBondingCurveAuthority authority;

    function setUp() public override {
        super.setUp();
        authority = new MockBondingCurveAuthority(payable(address(this)), 100, 100);
    }

    function test_checkBondingCurvePrice_firstMints() public {
        uint256 previousSupply = 0;

        for (uint i = 1; i < 10; i++) {
            // Check if buying i works as expected
            uint256 expectedBondingCurvePrice = 0;

            for (uint j = 1; j <= i; j++) {
                expectedBondingCurvePrice +=
                    (1 ether * (previousSupply + j - 1) * (previousSupply + j - 1)) /
                    50_000 +
                    0.001 ether;
            }

            emit log_named_uint("Num items to price for", i);
            emit log_uint(expectedBondingCurvePrice);

            assertEq(authority.getBondingCurvePrice(previousSupply, i), expectedBondingCurvePrice);
        }
    }

    function test_checkBondingCurvePrice_existingSupply() public {
        for (uint i = 0; i < 10; i++) {
            // Check if buying 3 works as expected with random existing supply 10 times
            uint256 expectedBondingCurvePrice = 0;
            uint256 previousSupply = _randomRange(1, 100);

            for (uint j = 1; j <= 3; j++) {
                expectedBondingCurvePrice +=
                    (1 ether * (previousSupply + j - 1) * (previousSupply + j - 1)) /
                    50_000 +
                    0.001 ether;
            }

            emit log_named_uint("Previous supply", previousSupply);
            emit log_uint(expectedBondingCurvePrice);

            assertEq(authority.getBondingCurvePrice(previousSupply, 3), expectedBondingCurvePrice);
        }
    }
}

contract MockBondingCurveAuthority is BondingCurveAuthority {
    constructor(
        address payable partyDao,
        uint16 initialPartyDaoFeeBps,
        uint16 initialTreasuryFeeBps
    ) BondingCurveAuthority(partyDao, initialPartyDaoFeeBps, initialTreasuryFeeBps) {}

    function getBondingCurvePrice(
        uint256 lowerSupply,
        uint256 amount
    ) external pure returns (uint256) {
        return super._getBondingCurvePrice(lowerSupply, amount);
    }
}
