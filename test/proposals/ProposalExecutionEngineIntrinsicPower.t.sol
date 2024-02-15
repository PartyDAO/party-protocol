// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { ProposalExecutionEngine } from "contracts/proposals/ProposalExecutionEngine.sol";

contract ProposalExecutionEngineIntrinsicVotingPowerTest is SetupPartyHelper {
    constructor() SetupPartyHelper(false) {}

    /// @notice All hints are correct
    function testIntrinsicVotingPowerAt_simpleTest() public {
        skip(10);
        uint40 firstTimestamp = uint40(block.timestamp);
        skip(10);
        party.increaseTotalVotingPower(50);
        party.mint(john, 50, john);
        uint40 secondTimestamp = uint40(block.timestamp);
        skip(100);

        assertEq(
            ProposalExecutionEngine(address(party)).getIntrinsicVotingPowerAt(
                john,
                firstTimestamp,
                0
            ),
            100
        );
        assertEq(
            ProposalExecutionEngine(address(party)).getIntrinsicVotingPowerAt(
                john,
                secondTimestamp,
                1
            ),
            150
        );
        assertEq(
            ProposalExecutionEngine(address(party)).getIntrinsicVotingPowerAt(
                john,
                uint40(block.timestamp),
                1
            ),
            150
        );
    }

    struct TestingSnapshots {
        uint40 timestamp;
        uint96 intrinsicVotingPower;
    }
    function testIntrinsicVotingPowerAt_advanced(
        uint8 numToMint,
        uint8 numToBurn,
        uint8 startBurnIndex
    ) external {
        vm.assume(numToMint > 5);
        vm.assume(numToMint < 20);
        vm.assume(numToBurn > 1);
        vm.assume(numToBurn < numToMint);
        vm.assume(startBurnIndex < numToMint - numToBurn);
        skip(10);

        TestingSnapshots[] memory snapshots = new TestingSnapshots[](numToMint + numToBurn + 1);
        snapshots[0] = TestingSnapshots(uint40(block.timestamp), 100);

        uint256[] memory newTokenIds = new uint256[](numToMint);

        for (uint i = 0; i < numToMint; i++) {
            skip(100);
            uint96 votingPower = uint96(_randomRange(1, 100));
            party.increaseTotalVotingPower(votingPower);
            newTokenIds[i] = party.mint(john, votingPower, john);
            snapshots[i + 1] = TestingSnapshots(
                uint40(block.timestamp),
                snapshots[i].intrinsicVotingPower + votingPower
            );
        }

        uint256 firstTokenToBurn = newTokenIds[startBurnIndex];
        for (uint i = firstTokenToBurn; i < firstTokenToBurn + numToBurn; i++) {
            skip(100);
            uint96 votingPower = uint96(party.votingPowerByTokenId(i));
            party.burn(i);
            uint256 previousSnapshot = numToMint + (i - firstTokenToBurn);
            snapshots[previousSnapshot + 1] = TestingSnapshots(
                uint40(block.timestamp),
                snapshots[previousSnapshot].intrinsicVotingPower - votingPower
            );
        }

        skip(100);

        for (uint i = 0; i < snapshots.length; i++) {
            assertEq(
                ProposalExecutionEngine(address(party)).getIntrinsicVotingPowerAt(
                    john,
                    snapshots[i].timestamp,
                    i + 1
                ),
                snapshots[i].intrinsicVotingPower
            );
        }
    }
}
