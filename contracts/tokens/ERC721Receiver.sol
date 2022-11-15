// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./IERC721Receiver.sol";
import "../utils/EIP165.sol";
import "../vendor/solmate/ERC721.sol";

/// @notice Mixin for contracts that want to receive ERC721 tokens.
/// @dev Use this instead of solmate's ERC721TokenReceiver because the
///      compiler has issues when overriding EIP165/IERC721Receiver functions.
abstract contract ERC721Receiver is IERC721Receiver, EIP165, ERC721TokenReceiver {
    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override(IERC721Receiver, ERC721TokenReceiver) returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @inheritdoc EIP165
    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return
            EIP165.supportsInterface(interfaceId) ||
            interfaceId == type(IERC721Receiver).interfaceId;
    }
}
