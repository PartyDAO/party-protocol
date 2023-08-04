// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { Party } from "../party/Party.sol";
import { IERC721 } from "../tokens/IERC721.sol";
import { MetadataProvider } from "../renderers/MetadataProvider.sol";

// Creates generic Party instances.
interface IPartyFactory {
    event PartyCreated(
        Party indexed party,
        Party.PartyOptions opts,
        IERC721[] preciousTokens,
        uint256[] preciousTokenIds,
        address creator
    );

    /// @notice Deploy a new party instance.
    /// @param partyImpl The implementation of the party to deploy.
    /// @param authorities The addresses set as authorities for the party.
    /// @param opts Options used to initialize the party. These are fixed
    ///             and cannot be changed later.
    /// @param preciousTokens The tokens that are considered precious by the
    ///                       party.These are protected assets and are subject
    ///                       to extra restrictions in proposals vs other
    ///                       assets.
    /// @param preciousTokenIds The IDs associated with each token in `preciousTokens`.
    /// @param rageQuitTimestamp The timestamp until which ragequit is enabled.
    /// @return party The newly created `Party` instance.
    function createParty(
        Party partyImpl,
        address[] memory authorities,
        Party.PartyOptions calldata opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        uint40 rageQuitTimestamp
    ) external returns (Party party);

    /// @notice Deploy a new party instance with custom metadata.
    /// @param partyImpl The implementation of the party to deploy.
    /// @param authorities The addresses set as authorities for the party.
    /// @param opts Options used to initialize the party.
    /// @param preciousTokens The tokens that are considered precious by the
    ///                       party.These are protected assets and are subject
    ///                       to extra restrictions in proposals vs other
    ///                       assets.
    /// @param preciousTokenIds The IDs associated with each token in `preciousTokens`.
    /// @param rageQuitTimestamp The timestamp until which ragequit is enabled.
    /// @param provider The metadata provider to use for the party.
    /// @param metadata The metadata to use for the party.
    /// @return party The newly created `Party` instance.
    function createPartyWithMetadata(
        Party partyImpl,
        address[] memory authorities,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        uint40 rageQuitTimestamp,
        MetadataProvider provider,
        bytes memory metadata
    ) external returns (Party party);
}
