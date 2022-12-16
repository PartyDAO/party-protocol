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
        address authority,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) external returns (Party party) {
        // Ensure a valid authority is set to mint governance NFTs.
        if (authority == address(0)) {
            revert InvalidAuthorityError(authority);
        }
        // Create the party.
        return _createParty(authority, opts, preciousTokens, preciousTokenIds);
    }

    function createPartyFromList(
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        bytes32 listMerkleRoot
    ) public returns (Party party) {
        // Create the party.
        party = _createParty(address(PARTY_LIST), opts, preciousTokens, preciousTokenIds);
        // Create the list used to determine the initial list of members and voting
        // power for each member.
        PARTY_LIST.createList(party, listMerkleRoot);
    }

    function _createParty(
        address authority,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) private returns (Party party) {
        // Deploy a new proxified `Party` instance.
        Party.PartyInitData memory initData = Party.PartyInitData({
            options: opts,
            preciousTokens: preciousTokens,
            preciousTokenIds: preciousTokenIds,
            mintAuthority: authority
        });
        party = Party(
            payable(
                new Proxy(
                    GLOBALS.getImplementation(LibGlobals.GLOBAL_PARTY_IMPL),
                    abi.encodeCall(Party.initialize, (initData))
                )
            )
        );
        emit PartyCreated(party, opts, preciousTokens, preciousTokenIds, msg.sender);
    }
}
