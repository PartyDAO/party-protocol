// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC721.sol";
import "../utils/Proxy.sol";

import "./Party.sol";
import "./IPartyFactory.sol";

// Creates generic Party instances.
contract PartyFactory is IPartyFactory {

    error InvalidAuthorityError(address authority);

    IGlobals public immutable GLOBALS;

    constructor(IGlobals globals) {
        GLOBALS = globals;
    }

    /// @inheritdoc IPartyFactory
    function createParty(
        address authority,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        external
        returns (Party party)
    {
        if (authority == address(0)) {
            revert InvalidAuthorityError(authority);
        }
        Party.PartyInitData memory initData = Party.PartyInitData({
            options: opts,
            preciousTokens: preciousTokens,
            preciousTokenIds: preciousTokenIds,
            mintAuthority: authority
        });
        party = Party(payable(
            new Proxy(
                GLOBALS.getImplementation(LibGlobals.GLOBAL_PARTY_IMPL),
                abi.encodeCall(Party.initialize, (initData))
            )
        ));
        emit PartyCreated(party, msg.sender);
    }
}
