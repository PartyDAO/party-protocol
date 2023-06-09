// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC721.sol";
import "../utils/Proxy.sol";
import "../renderers/RendererStorage.sol";

import "./Party.sol";
import "./IPartyFactory.sol";
import "./PartyList.sol";

/// @notice Factory used to deploy new proxified `Party` instances.
contract PartyFactory is IPartyFactory {
    error InvalidAuthorityError(address authority);

    IGlobals public immutable GLOBALS;
    PartyList public immutable PARTY_LIST;

    // Set the `Globals` contract.
    constructor(IGlobals globals, PartyList partyList) {
        GLOBALS = globals;
        PARTY_LIST = partyList;
    }

    function createParty(
        Party.PartyOpts memory opts,
        address mintAuthority
    ) external returns (Party party) {
        // Ensure a valid authority is set to mint governance NFTs.
        if (mintAuthority == address(0)) {
            revert InvalidAuthorityError(mintAuthority);
        }
        // Create the party.
        return _createParty(opts, mintAuthority);
    }

    function createPartyFromList(PartyFromListOpts memory opts) public returns (Party party) {
        // Create the party.
        party = _createParty(opts.partyOpts, address(PARTY_LIST));
        // Create the list used to determine the initial list of members and voting
        // power for each member and mint the party creator their card.
        PARTY_LIST.createList(
            party,
            opts.listMerkleRoot,
            opts.creator,
            opts.creatorVotingPower,
            opts.creatorDelegate
        );
        // Transfer the tokens to the party.
        for (uint256 i; i < opts.tokens.length; ++i) {
            opts.tokens[i].transferFrom(msg.sender, address(party), opts.tokenIds[i]);
        }
    }

    function _createParty(
        Party.PartyOpts memory opts,
        address mintAuthority
    ) private returns (Party party) {
        // Deploy a new proxified `Party` instance.
        party = Party(
            payable(
                new Proxy(
                    GLOBALS.getImplementation(LibGlobals.GLOBAL_PARTY_IMPL),
                    abi.encodeCall(Party.initialize, (opts, mintAuthority))
                )
            )
        );
        emit PartyCreated(party, opts, mintAuthority, msg.sender);
    }
}
