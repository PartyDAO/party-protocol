// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { IGlobals } from "../globals/IGlobals.sol";
import { LibGlobals } from "../globals/LibGlobals.sol";
import { IPartyFactory } from "../party/IPartyFactory.sol";
import { Party } from "../party/Party.sol";
import { IERC721 } from "../tokens/IERC721.sol";
import { MetadataProvider } from "../renderers/MetadataProvider.sol";

/// @title AtomicManualParty
/// @notice Singleton that is called to create a party manually with an array
///         of party members and their voting power.
contract AtomicManualParty {
    /// @notice Returned if the `AtomicManualParty` is created with no members
    error NoPartyMembers();
    /// @notice Returned if the lengths of `partyMembers` and `partyMemberVotingPower` do not match
    error PartyMembersArityMismatch();
    /// @notice Returned if a party card would be issued to the null address
    error InvalidPartyMember();
    /// @notice Returned if a party card would be issued with no voting power
    error InvalidPartyMemberVotingPower();

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    /// @notice Atomically creates the party and distributes the party cards
    function createParty(
        Party partyImpl,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        uint40 rageQuitTimestamp,
        address[] memory partyMembers,
        uint96[] memory partyMemberVotingPower
    ) public returns (Party party) {
        uint96 totalVotingPower = _validateAtomicManualPartyArrays(
            partyMembers,
            partyMemberVotingPower
        );

        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        opts.governance.totalVotingPower = totalVotingPower;

        party = IPartyFactory(_GLOBALS.getAddress(LibGlobals.GLOBAL_PARTY_FACTORY)).createParty(
            partyImpl,
            authorities,
            opts,
            preciousTokens,
            preciousTokenIds,
            rageQuitTimestamp
        );

        _issuePartyCards(party, partyMembers, partyMemberVotingPower);
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
        uint96[] memory partyMemberVotingPower
    ) external returns (Party party) {
        uint96 totalVotingPower = _validateAtomicManualPartyArrays(
            partyMembers,
            partyMemberVotingPower
        );

        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        opts.governance.totalVotingPower = totalVotingPower;

        party = IPartyFactory(_GLOBALS.getAddress(LibGlobals.GLOBAL_PARTY_FACTORY))
            .createPartyWithMetadata(
                partyImpl,
                authorities,
                opts,
                preciousTokens,
                preciousTokenIds,
                rageQuitTimestamp,
                provider,
                metadata
            );

        _issuePartyCards(party, partyMembers, partyMemberVotingPower);
    }

    /// @notice Issue party cards to the party members
    /// @param party The party to issue cards for
    /// @param partyMembers The party members to issue cards to
    /// @param partyMemberVotingPower The voting power each party member gets
    function _issuePartyCards(
        Party party,
        address[] memory partyMembers,
        uint96[] memory partyMemberVotingPower
    ) internal {
        for (uint256 i; i < partyMembers.length; i++) {
            party.mint(partyMembers[i], partyMemberVotingPower[i], partyMembers[i]);
        }
        party.abdicateAuthority();
    }

    /// @notice Validate manual party cards arrays, returns total voting power
    /// @param partyMembers The party members to issue cards to
    /// @param partyMemberVotingPower The voting power each party member gets
    /// @return totalVotingPower The total voting power of the party
    function _validateAtomicManualPartyArrays(
        address[] memory partyMembers,
        uint96[] memory partyMemberVotingPower
    ) private pure returns (uint96 totalVotingPower) {
        if (partyMembers.length == 0) {
            revert NoPartyMembers();
        }
        if (partyMembers.length != partyMemberVotingPower.length) {
            revert PartyMembersArityMismatch();
        }

        for (uint256 i = 0; i < partyMemberVotingPower.length; ++i) {
            if (partyMemberVotingPower[i] == 0) {
                revert InvalidPartyMemberVotingPower();
            }
            if (partyMembers[i] == address(0)) {
                revert InvalidPartyMember();
            }
            totalVotingPower += partyMemberVotingPower[i];
        }
    }
}
