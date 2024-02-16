// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { PartyGovernance } from "./../party/PartyGovernance.sol";
import { IERC20 } from "../tokens/IERC20.sol";
import { LibSafeCast } from "../utils/LibSafeCast.sol";
import { LibERC20Compat } from "./../utils/LibERC20Compat.sol";
import { LibAddress } from "./../utils/LibAddress.sol";

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
    event Distributed(IERC20 token, address[] members, uint256 amount);

    error NotEnoughETH(uint256 expectedAmount, uint256 receivedAmount);
    error UnexpectedETH(uint256 amount);
    error WrongProposalId(uint256 proposalId);
    error WrongMembers();
    error MembersNotSorted();

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
            if (msg.value < amount) revert NotEnoughETH(amount, msg.value);
        } else {
            if (msg.value != 0) revert UnexpectedETH(msg.value);
            token.compatTransferFrom(msg.sender, address(this), amount);
        }

        uint40 proposedTime;
        uint96 totalVotingPower;
        {
            (, PartyGovernance.ProposalStateValues memory proposal) = party.getProposalStateInfo(
                proposalId
            );

            if (proposal.executedTime != block.timestamp) revert WrongProposalId(proposalId);

            proposedTime = proposal.proposedTime;
            totalVotingPower = proposal.totalVotingPower;
        }

        address prevMember;
        uint96 totalIntrinsicVotingPower;
        for (uint256 i = 0; i < members.length; i++) {
            address member = members[i];

            // Prevent duplicate members to prevent members array manipulation.
            // For example, a member being replace with another duplicate member
            // that has the same voting power.
            if (member <= prevMember) revert MembersNotSorted();

            prevMember = member;

            uint96 intrinsicVotingPower = party.getIntrinsicVotingPowerAt(member, proposedTime, 0);

            totalIntrinsicVotingPower += intrinsicVotingPower;

            uint256 shareAmount = (amount * intrinsicVotingPower) / totalVotingPower;

            if (shareAmount > 0) {
                // Transfer the share of the distribution to the member.
                _transfer(token, member, shareAmount);
            }
        }

        // If the total intrinsic voting power is not equal to the total voting power,
        // it means that the members array is incorrect.
        if (totalIntrinsicVotingPower != totalVotingPower) revert WrongMembers();

        // Send back any remaining tokens to the sender.
        uint256 remainingAmount = token == ETH_ADDRESS
            ? address(this).balance
            : token.balanceOf(address(this));
        if (remainingAmount > 0) {
            _transfer(token, msg.sender, remainingAmount);
        }

        emit Distributed(token, members, amount);
    }

    function _transfer(IERC20 token, address to, uint256 amount) internal {
        if (token == ETH_ADDRESS) {
            // Do not revert on failure. Set gas to 100k to prevent consuming
            // all gas.
            payable(to).call{ value: amount, gas: 100_000 }("");
        } else {
            token.compatTransfer(to, amount);
        }
    }
}
