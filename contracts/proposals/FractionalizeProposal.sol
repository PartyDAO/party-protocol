// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../tokens/IERC721.sol";
import "../party/PartyGovernance.sol";

import "./IProposalExecutionEngine.sol";
import "./vendor/FractionalV1.sol";

// Implements fractionalizing an NFT to ERC20s on Fractional V1. Inherited by the `ProposalExecutionEngine`.
// This contract will be delegatecall'ed into by `Party` proxy instances.
contract FractionalizeProposal {
    struct FractionalizeProposalData {
        // The ERC721 token contract to fractionalize.
        IERC721 token;
        // The ERC721 token ID to fractionalize.
        uint256 tokenId;
    }

    event FractionalV1VaultCreated(
        IERC721 indexed token,
        uint256 indexed tokenId,
        uint256 vaultId,
        IERC20 vault
    );

    /// @notice Deployment of https://github.com/fractional-company/contracts/blob/master/src/ERC721TokenVault.sol.
    IFractionalV1VaultFactory public immutable VAULT_FACTORY;

    // Set the `VAULT_FACTORY`.
    constructor(IFractionalV1VaultFactory vaultFactory) {
        VAULT_FACTORY = vaultFactory;
    }

    // Fractionalize an NFT held by this party on Fractional V1.
    function _executeFractionalize(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal returns (bytes memory nextProgressData) {
        // Decode the proposal data.
        FractionalizeProposalData memory data = abi.decode(
            params.proposalData,
            (FractionalizeProposalData)
        );
        // The supply of fractional vault ERC20 tokens will be equal to the total
        // voting power of the party.
        uint256 supply = PartyGovernance(address(this)).getGovernanceValues().totalVotingPower;
        // Create a vault around the NFT.
        data.token.approve(address(VAULT_FACTORY), data.tokenId);
        uint256 vaultId = VAULT_FACTORY.mint(
            IERC721(address(this)).name(),
            IERC721(address(this)).symbol(),
            data.token,
            data.tokenId,
            supply,
            // Since we are distributing the entire supply immediately after
            // fractionalizing, in practice setting an initial reserve price
            // does not do anything because it will get reset to 0 after the
            // distribution is created.
            0,
            0
        );
        // Get the vault we just created.
        IFractionalV1Vault vault = VAULT_FACTORY.vaults(vaultId);
        // Check that we now hold the correct amount of fractional tokens.
        // Should always succeed.
        assert(vault.balanceOf(address(this)) == supply);
        // Remove ourselves as curator. Set to `address(1)` to avoid issues with
        // reverting when minting to `address(0)`.
        vault.updateCurator(address(1));
        emit FractionalV1VaultCreated(data.token, data.tokenId, vaultId, vault);
        // Create distribution for fractional tokens for party.
        PartyGovernance(address(this)).distribute(
            ITokenDistributor.TokenType.Erc20,
            address(vault),
            vaultId
        );
        // Nothing left to do.
        return "";
    }
}
