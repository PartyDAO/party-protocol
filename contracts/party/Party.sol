// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../tokens/IERC721.sol";

import "./PartyGovernanceNFT.sol";
import "./PartyGovernance.sol";

/// @notice The governance contract that also custodies the precious NFTs. This
///         is also the Governance NFT 721 contract.
contract Party is PartyGovernanceNFT {
    // Arguments used to initialize the party.
    struct PartyOptions {
        PartyGovernance.GovernanceOpts governance;
        string name;
        string symbol;
        uint256 customizationPresetId;
    }

    // Arguments used to initialize the `PartyGovernanceNFT`.
    struct PartyInitData {
        PartyOptions options;
        IERC721[] preciousTokens;
        uint256[] preciousTokenIds;
        address mintAuthority;
    }

    // Set the `Globals` contract.
    constructor(IGlobals globals) PartyGovernanceNFT(globals) {}

    /// @notice Initializer to be delegatecalled by `Proxy` constructor. Will
    ///         revert if called outside the constructor.
    /// @param initData Options used to initialize the party governance.
    function initialize(PartyInitData memory initData) external onlyConstructor {
        PartyGovernanceNFT._initialize(
            initData.options.name,
            initData.options.symbol,
            initData.options.customizationPresetId,
            initData.options.governance,
            initData.preciousTokens,
            initData.preciousTokenIds,
            initData.mintAuthority
        );
    }

    receive() external payable {}
}
