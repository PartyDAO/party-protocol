// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { Party } from "../party/Party.sol";
import { PartyGovernanceNFT } from "../party/PartyGovernanceNFT.sol";

contract AddPartyCardsAuthority {
    /// @notice Returned if the `AtomicManualParty` is created with no members
    error NoPartyMembers();
    /// @notice Returned if the lengths of `partyMembers` and `partyMemberVotingPowers` do not match
    error PartyMembersArityMismatch();
    /// @notice Returned if a party card would be issued to the null address
    error InvalidPartyMember();
    /// @notice Returned if a party card would be issued with no voting power
    error InvalidPartyMemberVotingPower();

    /// @notice Atomically distributes new party cards and updates the total voting power as needed.
    /// @dev Called must be the party and this contract must be an authority on the party
    /// @param newPartyMembers Addresses of the new party members (duplicates allowed)
    /// @param newPartyMemberVotingPowers Voting powers for the new party cards
    /// @param initialDelegates Initial delegates for the new party members. If the member already set a delegate this is ignored.
    function addPartyCards(
        address[] calldata newPartyMembers,
        uint96[] calldata newPartyMemberVotingPowers,
        address[] calldata initialDelegates
    ) external {
        if (newPartyMembers.length == 0) {
            revert NoPartyMembers();
        }
        if (newPartyMembers.length != newPartyMemberVotingPowers.length) {
            revert PartyMembersArityMismatch();
        }

        uint96 addedVotingPower;
        for (uint256 i; i < newPartyMemberVotingPowers.length; ++i) {
            if (newPartyMemberVotingPowers[i] == 0) {
                revert InvalidPartyMemberVotingPower();
            }
            if (newPartyMembers[i] == address(0)) {
                revert InvalidPartyMember();
            }
            addedVotingPower += newPartyMemberVotingPowers[i];
        }
        Party(payable(msg.sender)).increaseTotalVotingPower(addedVotingPower);

        for (uint256 i; i < newPartyMembers.length; ++i) {
            PartyGovernanceNFT(msg.sender).mint(
                newPartyMembers[i],
                newPartyMemberVotingPowers[i],
                initialDelegates[i]
            );
        }
    }
}
