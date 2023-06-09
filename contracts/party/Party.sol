// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../tokens/IERC721.sol";

import "./PartyGovernanceNFT.sol";
import "./PartyGovernance.sol";

/// @notice The governance contract that also custodies the precious NFTs. This
///         is also the Governance NFT 721 contract.
contract Party is PartyGovernanceNFT {
    struct PartyOpts {
        // The name of the party.
        string name;
        // The symbol of the party.
        string symbol;
        // Preset ID to use for customizing rendering of governance NFTs.
        uint256 customizationPresetId;
        // Hash of tokens and token IDs that are considered precious by the
        // party. These are protected assets and are subject to extra
        // restrictions in proposals vs other assets. This is used to verify
        // that the list of precious tokens and token IDs is correct.
        bytes32 preciousListHash;
        // Options used to initialize the party governance.
        PartyGovernance.GovernanceOpts governance;
    }

    // Set the `Globals` contract.
    constructor(IGlobals globals) PartyGovernanceNFT(globals) {}

    /// @notice Initializer to be delegatecalled by `Proxy` constructor. Will
    ///         revert if called outside the constructor.
    /// @param opts Options used to initialize the party governance.
    function initialize(PartyOpts memory opts, address mintAuthority) external onlyConstructor {
        PartyGovernanceNFT._initialize(opts, mintAuthority);
    }

    receive() external payable {}
}
