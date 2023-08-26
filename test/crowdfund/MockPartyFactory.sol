// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../../contracts/party/IPartyFactory.sol";
import "./MockParty.sol";

contract MockPartyFactory is IPartyFactory {
    MockParty public mockParty = new MockParty();

    event MockPartyFactoryCreateParty(
        address caller,
        address[] authorities,
        Party.PartyOptions opts,
        IERC721[] preciousTokens,
        uint256[] preciousTokenIds
    );

    function createParty(
        Party,
        address[] memory authorities,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        uint40
    ) external returns (Party party) {
        emit MockPartyFactoryCreateParty(
            msg.sender,
            authorities,
            opts,
            preciousTokens,
            preciousTokenIds
        );
        return Party(payable(address(mockParty)));
    }

    function createPartyWithMetadata(
        Party,
        address[] memory authorities,
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        uint40,
        MetadataProvider,
        bytes memory
    ) external returns (Party party) {
        emit MockPartyFactoryCreateParty(
            msg.sender,
            authorities,
            opts,
            preciousTokens,
            preciousTokenIds
        );
        return Party(payable(address(mockParty)));
    }
}
