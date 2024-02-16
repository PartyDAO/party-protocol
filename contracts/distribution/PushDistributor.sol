// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { PartyGovernance } from "./../party/PartyGovernance.sol";
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
        address voter,
        uint40 timestamp,
        uint256 hintIndex
    ) external view returns (uint96);
    function getProposalStateInfo(
        uint256 proposalId
    )
        external
        view
        returns (
            PartyGovernance.ProposalStatus status,
            PartyGovernance.ProposalStateValues memory values
        );
}

contract PushDistributor {
    using LibSafeCast for uint256;
    using LibERC20Compat for IERC20;
    using LibAddress for address payable;

    // Token address used to indicate ETH.
    IERC20 private constant ETH_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    function distribute(
        IERC20 token,
        address[] memory members,
        uint256 amount,
        uint256 proposalId
    ) external payable {
        IParty party = IParty(payable(msg.sender));
        if (token == ETH_ADDRESS) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            require(msg.value == 0, "Unexpected ETH amount");
            token.compatTransferFrom(msg.sender, address(this), amount);
        }

        uint40 proposedTime;
        uint96 totalVotingPower;
        {
            (
                PartyGovernance.ProposalStatus status,
                PartyGovernance.ProposalStateValues memory proposal
            ) = party.getProposalStateInfo(proposalId);

            require(
                status == PartyGovernance.ProposalStatus.Complete &&
                    proposal.executedTime == block.timestamp,
                "Wrong proposal ID"
            );

            proposedTime = proposal.proposedTime;
            totalVotingPower = party.getGovernanceValues().totalVotingPower;
        }

        address prevMember;
        uint96 totalIntrinsicVotingPower;
        for (uint256 i = 0; i < members.length; i++) {
            address member = members[i];

            // Prevent duplicate members to prevent members array manipulation.
            // For example, a member being replace with another duplicate member
            // that has the same voting power.
            require(member > prevMember, "Members not sorted");

            prevMember = member;

            uint96 intrinsicVotingPower = party.getIntrinsicVotingPowerAt(member, proposedTime, 0);

            totalIntrinsicVotingPower += intrinsicVotingPower;

            uint256 shareAmount = (amount * intrinsicVotingPower) / totalVotingPower;

            if (shareAmount > 0) {
                // Transfer the share of the distribution to the member.
                if (token == ETH_ADDRESS) {
                    payable(member).transferEth(shareAmount);
                } else {
                    token.compatTransfer(member, shareAmount);
                }
            }
        }

        require(totalIntrinsicVotingPower == totalVotingPower, "Missing member");
    }
}
