// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC721.sol";
import "../utils/Proxy.sol";
import "../renderers/RendererStorage.sol";

import "./Party.sol";
import "./IPartyFactory.sol";

/// @notice Factory used to deploy new proxified `Party` instances.
contract PartyFactory is IPartyFactory {
    error InvalidAuthorityError(address authority);

    /// @inheritdoc IPartyFactory
    IGlobals public immutable GLOBALS;

    // Set the `Globals` contract.
    constructor(IGlobals globals) {
        GLOBALS = globals;
    }

    /// @inheritdoc IPartyFactory
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
