// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

abstract contract EIP165 {
    /// @notice Query if a contract implements an interface.
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return `true` if the contract implements `interfaceId` and
    ///         `interfaceId` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceId)
        public
        virtual
        pure
        returns (bool)
    {
        return interfaceId == this.supportsInterface.selector;
    }
}
