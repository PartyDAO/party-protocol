// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../../contracts/party/IPartyFactory.sol";
import "./MockParty.sol";

contract MockPartyFactory is IPartyFactory {
    MockParty public mockParty = new MockParty();

    event MockPartyFactoryCreateParty(
        address caller,
        address authority,
        Party.PartyOptions opts,
        address[] preciousTokens,
        uint256[] preciousTokenIds
    );

    function GLOBALS() external pure returns (IGlobals g) {}

    function abdicate(Party) external {}

    function createParty(
        address authority,
        Party.PartyOptions memory opts,
        address[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) external returns (Party party) {
        emit MockPartyFactoryCreateParty(
            msg.sender,
            authority,
            opts,
            preciousTokens,
            preciousTokenIds
        );
        return Party(payable(address(mockParty)));
    }
}
