// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../../tokens/IERC20.sol";
import "../../tokens/IERC721.sol";

/// @dev FractionalVaultFactory interface from
/// https://github.com/fractional-company/contracts/blob/643bb669ad71aac8d1b11f0300c9bb0dec494daa/src/ERC721VaultFactory.sol
interface IFractionalV1VaultFactory {
    function vaultCount() external view returns (uint256 count);

    function vaults(uint256 vaultId) external view returns (IFractionalV1Vault vault);

    function mint(
        string calldata name,
        string calldata symbol,
        IERC721 token,
        uint256 tokenId,
        uint256 supply,
        uint256 listPrice,
        uint256 fee
    ) external returns (uint256 vaultId);
}

/// @dev ERC721TokenVault interface from
/// https://github.com/fractional-company/contracts/blob/d4faa2dddf010d12b87eae8054f485656c8ed14b/src/ERC721TokenVault.sol
interface IFractionalV1Vault is IERC20 {
    function curator() external view returns (address curator_);

    function auctionEnd() external view returns (uint256);

    function reservePrice() external view returns (uint256);

    function livePrice() external view returns (uint256);

    function winning() external view returns (address);

    function updateCurator(address curator_) external;

    function updateUserPrice(uint256) external;

    function start() external payable;

    function bid() external payable;

    function end() external;

    function redeem() external;

    function cash() external;
}
