// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "contracts/party/Party.sol";
import "./MockParty.sol";

contract MockPartyFactory {
    MockParty public mockParty = new MockParty();

    event MockPartyFactoryCreateParty(address caller, Party.PartyOpts opts, address authority);

    function GLOBALS() external pure returns (IGlobals g) {}

    function abdicate(Party) external {}

    function createParty(
        Party.PartyOpts memory opts,
        address authority
    ) external returns (Party party) {
        emit MockPartyFactoryCreateParty(msg.sender, opts, authority);
        return Party(payable(address(mockParty)));
    }
}
