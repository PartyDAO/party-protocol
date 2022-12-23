// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../vendor/solmate/ERC1155.sol";
import "../utils/EIP165.sol";

abstract contract ERC1155Receiver is EIP165, ERC1155TokenReceiverBase {
    /// @inheritdoc EIP165
    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(ERC1155TokenReceiverBase).interfaceId;
    }
}
