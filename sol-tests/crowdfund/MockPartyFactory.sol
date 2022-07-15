// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../../contracts/party/IPartyFactory.sol";


contract MockPartyFactory is IPartyFactory {
    Party public constant mockParty = Party(payable(address(0xabba)));

    event MockPartyFactoryCreateParty(
        address caller,
        address authority,
        Party.PartyOptions opts,
        IERC721[] preciousTokens,
        uint256[] preciousTokenIds
    );

    event MockPartyFactoryMint(
        address caller,
        Party party,
        address owner,
        uint256 amount,
        address delegate
    );

    function GLOBALS() external pure returns (IGlobals g) {}
    function abdicate(Party) external {}

    function createParty(
        address authority,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        external
        returns (Party party)
    {
        emit MockPartyFactoryCreateParty(
            msg.sender,
            authority,
            opts,
            preciousTokens,
            preciousTokenIds
        );
        return mockParty;
    }

    function mint(
        Party party,
        address owner,
        uint256 amount,
        address delegate
    )
        external
    {
        emit MockPartyFactoryMint(msg.sender, party, owner, amount, delegate);
    }
}
