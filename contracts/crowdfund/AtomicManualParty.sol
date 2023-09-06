// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { IPartyFactory } from "../party/IPartyFactory.sol";
import { Party } from "../party/Party.sol";
import { IERC721 } from "../tokens/IERC721.sol";
import { MetadataProvider } from "../renderers/MetadataProvider.sol";

/// @title AtomicManualParty
/// @notice Singleton that is called to create a party manually with an array
///         of party members and their voting power.
contract AtomicManualParty {
    /// @notice Emitted when an atomic manual party is created
    event AtomicManualPartyCreated(
        Party indexed party,
        address[] partyMembers,
        uint96[] partyMemberVotingPowers,
        Party.PartyOptions opts,
        IERC721[] preciousTokens,
        uint256[] preciousTokenIds,
        uint40 rageQuitTimestamp,
        address creator
    );
    /// @notice Returned if the `AtomicManualParty` is created with no members
    error NoPartyMembers();
    /// @notice Returned if the lengths of `partyMembers` and `partyMemberVotingPowers` do not match
    error PartyMembersArityMismatch();
    /// @notice Returned if a party card would be issued to the null address
    error InvalidPartyMember();
    /// @notice Returned if a party card would be issued with no voting power
    error InvalidPartyMemberVotingPower();

    IPartyFactory private immutable PARTY_FACTORY;

    constructor(IPartyFactory partyFactory) {
        PARTY_FACTORY = partyFactory;
    }

    /// @notice Atomically creates the party and distributes the party cards
    function createParty(
        Party partyImpl,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        uint40 rageQuitTimestamp,
        address[] memory partyMembers,
        uint96[] memory partyMemberVotingPowers
    ) public returns (Party party) {
        uint96 totalVotingPower = _validateAtomicManualPartyArrays(
            partyMembers,
            partyMemberVotingPowers
        );

        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        opts.governance.totalVotingPower = totalVotingPower;

        party = PARTY_FACTORY.createParty(
            partyImpl,
            authorities,
            opts,
            preciousTokens,
            preciousTokenIds,
            rageQuitTimestamp
        );

        _issuePartyCards(party, partyMembers, partyMemberVotingPowers);
        emit AtomicManualPartyCreated(
            party,
            partyMembers,
            partyMemberVotingPowers,
            opts,
            preciousTokens,
            preciousTokenIds,
            rageQuitTimestamp,
            msg.sender
        );
    }

    /// @notice Atomically creates the party and distributes the party cards
    ///         with metadata
    function createPartyWithMetadata(
        Party partyImpl,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        uint40 rageQuitTimestamp,
        MetadataProvider provider,
        bytes memory metadata,
        address[] memory partyMembers,
        uint96[] memory partyMemberVotingPowers
    ) external returns (Party party) {
        uint96 totalVotingPower = _validateAtomicManualPartyArrays(
            partyMembers,
            partyMemberVotingPowers
        );

        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        opts.governance.totalVotingPower = totalVotingPower;

        party = PARTY_FACTORY.createPartyWithMetadata(
            partyImpl,
            authorities,
            opts,
            preciousTokens,
            preciousTokenIds,
            rageQuitTimestamp,
            provider,
            metadata
        );

        _issuePartyCards(party, partyMembers, partyMemberVotingPowers);
        emit AtomicManualPartyCreated(
            party,
            partyMembers,
            partyMemberVotingPowers,
            opts,
            preciousTokens,
            preciousTokenIds,
            rageQuitTimestamp,
            msg.sender
        );
    }

    /// @notice Issue party cards to the party members and finishes up creation
    /// @param party The party to issue cards for
    /// @param partyMembers The party members to issue cards to
    /// @param partyMemberVotingPowers The voting power each party member gets
    function _issuePartyCards(
        Party party,
        address[] memory partyMembers,
        uint96[] memory partyMemberVotingPowers
    ) internal {
        for (uint256 i; i < partyMembers.length; i++) {
            party.mint(partyMembers[i], partyMemberVotingPowers[i], partyMembers[i]);
        }
        party.abdicateAuthority();
    }

    /// @notice Validate manual party cards arrays, returns total voting power
    /// @param partyMembers The party members to issue cards to
    /// @param partyMemberVotingPowers The voting power each party member gets
    /// @return totalVotingPower The total voting power of the party
    function _validateAtomicManualPartyArrays(
        address[] memory partyMembers,
        uint96[] memory partyMemberVotingPowers
    ) private pure returns (uint96 totalVotingPower) {
        if (partyMembers.length == 0) {
            revert NoPartyMembers();
        }
        if (partyMembers.length != partyMemberVotingPowers.length) {
            revert PartyMembersArityMismatch();
        }

        for (uint256 i = 0; i < partyMemberVotingPowers.length; ++i) {
            if (partyMemberVotingPowers[i] == 0) {
                revert InvalidPartyMemberVotingPower();
            }
            if (partyMembers[i] == address(0)) {
                revert InvalidPartyMember();
            }
            totalVotingPower += partyMemberVotingPowers[i];
        }
    }
}
