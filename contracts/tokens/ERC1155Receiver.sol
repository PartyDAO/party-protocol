// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../vendor/solmate/ERC1155.sol";
import "../utils/EIP165.sol";

contract ERC1155Receiver is EIP165, ERC1155TokenReceiverBase {

    /// @inheritdoc EIP165
    function supportsInterface(bytes4 interfaceId)
        public
        override
        virtual
        pure
        returns (bool)
    {
        if (interfaceId == 0x4e2312e0) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }

}
