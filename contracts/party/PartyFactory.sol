// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { Clones } from "openzeppelin/contracts/proxy/Clones.sol";

import { IERC721 } from "../tokens/IERC721.sol";

import { Party } from "./Party.sol";
import { IPartyFactory } from "./IPartyFactory.sol";
import { IGlobals } from "../globals/IGlobals.sol";
import { LibGlobals } from "../globals/LibGlobals.sol";
import { MetadataRegistry } from "../renderers/MetadataRegistry.sol";
import { MetadataProvider } from "../renderers/MetadataProvider.sol";

/// @notice Factory used to deploy new proxified `Party` instances.
contract PartyFactory is IPartyFactory {
    using Clones for address;

    error NoAuthorityError();

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    // Set immutables.
    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    /// @inheritdoc IPartyFactory
    function createParty(
        Party partyImpl,
        address[] memory authorities,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        uint40 rageQuitTimestamp
    ) public returns (Party party) {
        // Ensure an authority is set to mint governance NFTs.
        if (authorities.length == 0) {
            revert NoAuthorityError();
        }
        // Deploy a new proxified `Party` instance.
        Party.PartyInitData memory initData = Party.PartyInitData({
            options: opts,
            preciousTokens: preciousTokens,
            preciousTokenIds: preciousTokenIds,
            authorities: authorities,
            rageQuitTimestamp: rageQuitTimestamp
        });
        party = Party(payable(address(partyImpl).clone()));
        party.initialize(initData);
        emit PartyCreated(party, opts, preciousTokens, preciousTokenIds, msg.sender);
    }

    /// @inheritdoc IPartyFactory
    function createPartyWithMetadata(
        Party partyImpl,
        address[] memory authorities,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        uint40 rageQuitTimestamp,
        MetadataProvider provider,
        bytes memory metadata
    ) external returns (Party party) {
        party = createParty(
            partyImpl,
            authorities,
            opts,
            preciousTokens,
            preciousTokenIds,
            rageQuitTimestamp
        );

        MetadataRegistry registry = MetadataRegistry(
            _GLOBALS.getAddress(LibGlobals.GLOBAL_METADATA_REGISTRY)
        );

        // Set the metadata for the Party.
        registry.setProvider(address(party), provider);
        if (metadata.length > 0) provider.setMetadata(address(party), metadata);
    }
}
