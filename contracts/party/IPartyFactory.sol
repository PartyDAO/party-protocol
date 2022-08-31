// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../globals/IGlobals.sol";
import "../tokens/IERC721.sol";

import "./Party.sol";

// Creates generic Party instances.
interface IPartyFactory {
    event PartyCreated(Party party, address creator);

    // Deploy a new party instance. Afterwards, governance NFTs can be minted
    // for party members using the `Party.mint()` function from the newly created
    // party. `authority` is the address that can call `mint()`.
    function createParty(
        address authority,
        Party.PartyOptions calldata opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        external
        returns (Party party);

    function GLOBALS() external view returns (IGlobals);
}
