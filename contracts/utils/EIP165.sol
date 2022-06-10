// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

contract EIP165 {

    function supportsInterface(bytes4 interfaceId)
        public
        virtual
        pure
        returns (bool)
    {
        // EIP165
        if (interfaceId == 0x01ffc9a7) {
            return true;
        }
        return false;
    }
}
