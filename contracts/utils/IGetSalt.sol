// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

/// @notice Interface for contracts that specify a create2 deploy salt.
/// @dev For usage, see PartyFactory.
interface IGetSalt {
    /// @notice Return a salt to use in create2 operations originating from
    ///         this contract.
    function salt() external view returns (bytes32);
}
