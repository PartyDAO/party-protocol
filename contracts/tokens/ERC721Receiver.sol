// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./IERC721Receiver.sol";
import "../utils/EIP165.sol";

contract ERC721Receiver is IERC721Receiver, EIP165 {

    function onERC721Received(address, address, uint256, bytes memory)
        public
        virtual
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override
        returns (bool)
    {
        // IERC721Receiver
        if (interfaceId == 0x150b7a02) {
            return true;
        }
        return EIP165.supportsInterface(interfaceId);
    }
}
