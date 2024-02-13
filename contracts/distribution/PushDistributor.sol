// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { IERC20 } from "../tokens/IERC20.sol";
import { LibSafeCast } from "../utils/LibSafeCast.sol";
import { LibERC20Compat } from "./../utils/LibERC20Compat.sol";
import { LibAddress } from "./../utils/LibAddress.sol";

// TODO: Add tests
// TODO: Add events
// TODO: Add custom errors

interface IParty {
    struct GovernanceValues {
        uint40 voteDuration;
        uint40 executionDelay;
        uint16 passThresholdBps;
        uint96 totalVotingPower;
    }

    function getGovernanceValues() external view returns (GovernanceValues memory);
    function getIntrinsicVotingPowerAt(
        address member,
        uint256 timestamp,
        uint256 hintIndex
    ) external view returns (uint96);
}

contract PushDistributor {
    using LibSafeCast for uint256;
    using LibERC20Compat for IERC20;
    using LibAddress for address payable;

    // Token address used to indicate ETH.
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function distribute(IERC20 token, address[] memory members, uint256 amount) external payable {
        IParty party = IParty(payable(msg.sender));
        if (address(token) == ETH_ADDRESS) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            require(msg.value == 0, "Unexpected ETH amount");
            token.compatTransferFrom(msg.sender, address(this), amount);
        }

        address prevMember;
        uint96 totalIntrinsicVotingPower;
        uint96 totalVotingPower = party.getGovernanceValues().totalVotingPower;
        for (uint256 i = 0; i < members.length; i++) {
            address member = members[i];

            // Prevent duplicate members to prevent members array manipulation.
            // For example, a member being replace with another duplicate member
            // that has the same voting power.
            require(member > prevMember, "Members not sorted");

            prevMember = member;

            uint96 intrinsicVotingPower = party.getIntrinsicVotingPowerAt(
                member,
                block.timestamp,
                0
            );

            totalIntrinsicVotingPower += intrinsicVotingPower;

            uint256 share = ((intrinsicVotingPower) * 1e18) / totalVotingPower;

            // We round up here to prevent dust amounts getting trapped in this contract.
            uint256 shareAmount = (share * amount + (1e18 - 1)) / 1e18;

            if (shareAmount > 0) {
                // Transfer the share of the distribution to the member.
                if (address(token) == ETH_ADDRESS) {
                    payable(member).transferEth(amount);
                } else {
                    token.compatTransfer(member, amount);
                }
            }
        }

        require(totalIntrinsicVotingPower == totalVotingPower, "Missing member");
    }
}
