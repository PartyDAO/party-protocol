// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../../tokens/IERC20.sol";
import "../../tokens/IERC721.sol";

/// @dev FractionalVaultFactory interface from
/// https://github.com/fractional-company/contracts/blob/643bb669ad71aac8d1b11f0300c9bb0dec494daa/src/ERC721VaultFactory.sol
interface IFractionalV1VaultFactory {
    function vaults(uint256 vaultId) external view returns (IERC20 vault);

    function mint(
        string calldata name,
        string calldata symbol,
        IERC721 token,
        uint256 tokenId,
        uint256 supply,
        uint256 listPrice,
        uint256 fee
    )
        external
        returns (uint256 vaultId);
}
