// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../globals/IGlobals.sol";
import "../tokens/IERC721.sol";

import "./Party.sol";

// Creates generic Party instances.
interface IPartyFactory {
    event PartyCreated(Party party, address creator);

    // Deploy a new party instance. Afterwards, governance NFTs can be minted
    // for party members using the `PartyFactory.mint()` function.
    // `authority` is the address that can call `mint()`.
    function createParty(
        address authority,
        Party.PartyOptions calldata opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        external
        returns (Party party);

    // Relinquish the ability to call `mint()`` by an authority.
    function abdicate(Party party) external;

    // Mint governance tokens on a party created through this factory.
    // Only the authortiy set in `createParty()` can call this function.
    function mint(
        Party party,
        address owner,
        uint256 amount,
        address delegate
    )
        external;

    function GLOBALS() external view returns (IGlobals);
}
