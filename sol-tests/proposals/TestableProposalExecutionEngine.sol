// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/ProposalExecutionEngine.sol";

contract TestableProposalExecutionEngine is ProposalExecutionEngine {
    event TestEcho(uint256 indexed v);

    bytes public t_nextProgressData;

    modifier onlyDelegateCall() override {
        _;
    }

    constructor(
        IGlobals globals,
        IOpenseaExchange seaport,
        IOpenseaConduitController seaportConduitController,
        IZoraAuctionHouse zora,
        IFractionalV1VaultFactory fractionalVaultFactory
    )
        ProposalExecutionEngine(
            globals,
            seaport,
            seaportConduitController,
            zora,
            fractionalVaultFactory
        )
    {}

    function getProposalEngineImpl() external view returns (IProposalExecutionEngine) {
        return _getProposalExecutionEngine();
    }

    function _execute(
        ProposalExecutionEngine.ProposalType pt,
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal override returns (bytes memory nextProgressData) {
        // Override the ListOnOpensea proposal type to do a two step emit.
        if (pt == ProposalExecutionEngine.ProposalType.ListOnOpensea) {
            uint256 step = params.progressData.length == 0
                ? 0
                : abi.decode(params.progressData, (uint256));
            (uint256 emitValue1, uint256 emitValue2) = abi.decode(
                params.proposalData,
                (uint256, uint256)
            );
            if (step == 0) {
                emit TestEcho(emitValue1);
                return t_nextProgressData = abi.encode(1);
            }
            emit TestEcho(emitValue2);
            return ""; // Done
        }
        // Override the ListOnZora propsal type to do a one step emit.
        if (pt == ProposalExecutionEngine.ProposalType.ListOnZora) {
            uint256 emitValue = abi.decode(params.proposalData, (uint256));
            emit TestEcho(emitValue);
            return ""; // Done
        }
        return super._execute(pt, params);
    }

    function getNextProgressDataHash() external view returns (bytes32 nextProgressDataHash) {
        return _getStorage().nextProgressDataHash;
    }
}
