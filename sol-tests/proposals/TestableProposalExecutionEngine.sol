// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/ProposalExecutionEngine.sol";

contract TestableProposalExecutionEngine is ProposalExecutionEngine {

    event TestEcho(uint256 indexed v);

    bytes public t_nextProgressData;

    constructor(IGlobals globals, SharedWyvernV2Maker maker, IZoraAuctionHouse zora)
        ProposalExecutionEngine(globals, maker, zora)
    {}

    function getProposalEngineImpl()
        external
        view
        returns (IProposalExecutionEngine)
    {
        return LibProposal.getProposalExecutionEngine();
    }

    function _execute(
        ProposalExecutionEngine.ProposalType pt,
        IProposalExecutionEngine.ExecuteProposalParams memory params
    )
        internal
        override
        returns (bytes memory nextProgressData)
    {
        // Override the ListOnOpenSea proposal type to do a two step emit.
        if (pt == ProposalExecutionEngine.ProposalType.ListOnOpenSea) {
            uint256 step = params.progressData.length == 0
                ? 0
                : abi.decode(params.progressData, (uint256));
            (uint256 emitValue1, uint256 emitValue2) =
                abi.decode(params.proposalData, (uint256, uint256));
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
}
