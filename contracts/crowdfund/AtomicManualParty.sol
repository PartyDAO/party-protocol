// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { IGlobals } from "../globals/IGlobals.sol";
import { LibGlobals } from "../globals/LibGlobals.sol";
import { IPartyFactory } from "../party/IPartyFactory.sol";
import { Party } from "../party/Party.sol";
import { IERC721 } from "../tokens/IERC721.sol";
import { MetadataProvider } from "../renderers/MetadataProvider.sol";
import { Proxy } from "../utils/Proxy.sol";
import { Implementation } from "../utils/Implementation.sol";

/// @title AtomicManualParty
/// @notice Singleton that is called to create a party manually with an array
///         of party members and their votes.
contract AtomicManualParty {
    error PartyMembersArityMismatch();

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;
    IPartyFactory private immutable _PARTY_FACTORY;

    constructor(IGlobals globals, IPartyFactory partyFactory) {
        _GLOBALS = globals;
        _PARTY_FACTORY = partyFactory;
    }

    /// @notice Atomically creates the party and distributes the party cards
    function createParty(
        Party partyImpl,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        uint40 rageQuitTimestamp,
        address[] memory partyMembers,
        uint96[] memory partyMemberVotes
    ) public returns (Party party) {
        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        uint96 totalVotes = 0;
        for (uint256 i = 0; i < partyMemberVotes.length; i++) {
            totalVotes += partyMemberVotes[i];
        }
        opts.governance.totalVotingPower = totalVotes;

        party = _PARTY_FACTORY.createParty(
            partyImpl,
            authorities,
            opts,
            preciousTokens,
            preciousTokenIds,
            rageQuitTimestamp
        );

        _issuePartyCards(party, partyMembers, partyMemberVotes);
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
        uint96[] memory partyMemberVotes
    ) external returns (Party party) {
        address[] memory authorities = new address[](1);
        authorities[0] = address(this);

        uint96 totalVotes = 0;
        for (uint256 i = 0; i < partyMemberVotes.length; i++) {
            totalVotes += partyMemberVotes[i];
        }
        opts.governance.totalVotingPower = totalVotes;

        party = _PARTY_FACTORY.createPartyWithMetadata(
            partyImpl,
            authorities,
            opts,
            preciousTokens,
            preciousTokenIds,
            rageQuitTimestamp,
            provider,
            metadata
        );

        _issuePartyCards(party, partyMembers, partyMemberVotes);
    }

    /// @notice Issue party cards to the party members
    /// @param party The party to issue cards for
    /// @param partyMembers The party members to issue cards to
    /// @param partyMemberVotes The number of votes each party member gets
    function _issuePartyCards(
        Party party,
        address[] memory partyMembers,
        uint96[] memory partyMemberVotes
    ) internal {
        if (partyMembers.length != partyMemberVotes.length) {
            revert PartyMembersArityMismatch();
        }

        for (uint256 i = 0; i < partyMembers.length; i++) {
            party.mint(partyMembers[i], partyMemberVotes[i], partyMembers[i]);
        }
        party.abdicateAuthority();
    }
}