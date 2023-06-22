// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "../globals/IGlobals.sol";
import "../tokens/IERC721.sol";

import "./Party.sol";

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
}
