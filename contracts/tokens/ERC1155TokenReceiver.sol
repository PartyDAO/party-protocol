// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../vendor/solmate/ERC1155.sol";
import "../utils/EIP165.sol";

contract ERC1155TokenReceiver is EIP165, ERC1155TokenReceiverBase {

    function supportsInterface(bytes4 interfaceId)
        public
        override
        virtual
        pure
        returns (bool)
    {
        if (interfaceId == 0xd9b67a26) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }

}
