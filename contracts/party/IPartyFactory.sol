// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

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

    /// @notice Deploy a new party instance. Afterwards, governance NFTs can be minted
    ///         for party members by the authority (usually the crowdfund
    ///         instance, if created from a successful crowdfund) using the
    ///         `mint()` function.
    /// @param authority The address that can call `mint()`.
    /// @param opts Options used to initialize the party. These are fixed
    ///             and cannot be changed later.
    /// @param preciousTokens The tokens that are considered precious by the
    ///                       party.These are protected assets and are subject
    ///                       to extra restrictions in proposals vs other
    ///                       assets.
    /// @param preciousTokenIds The IDs associated with each token in `preciousTokens`.
    /// @return party The newly created `Party` instance.
    function createParty(
        address authority,
        Party.PartyOptions calldata opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) external returns (Party party);

    /// @notice Deploy a new party instance from a list of members and their
    ///         voting powers. Afterwards, governance NFTs can be minted for
    ///         party members through the `PartyList` contract using the `mint()` function.
    /// @param opts Options used to initialize the party. These are fixed
    ///             and cannot be changed later.
    /// @param preciousTokens The tokens that are considered precious by the
    ///                       party.These are protected assets and are subject
    ///                       to extra restrictions in proposals vs other
    ///                       assets.
    /// @param preciousTokenIds The IDs associated with each token in `preciousTokens`.
    /// @param listMerkleRoot Merkle root of list of initial members and
    ///                       voting power for each member. Each leaf in the
    ///                       list should be encoded as:
    ///                       `abi.encodePacked(address member, uint96 votingPower)`.
    /// @return party The newly created `Party` instance.
    function createPartyFromList(
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        bytes32 listMerkleRoot
    ) external returns (Party party);

    /// @notice The `Globals` contract storing global configuration values. This contract
    ///         is immutable and it’s address will never change.
    function GLOBALS() external view returns (IGlobals);
}
