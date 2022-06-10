// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/IProposalExecutionEngine.sol";

contract DummySimpleProposalEngineImpl is IProposalExecutionEngine {

    struct DummySimpleProposalEngineImplStorage {
        uint256 lastExecutedProposalId;
        uint256 executedProposals;
        mapping (uint256 => uint256) proposalIdToFlags;
    }

    // Storage slot for `DummySimpleProposalEngineImplStorage`.
    uint256 private immutable STORAGE_SLOT;

    constructor() {
        STORAGE_SLOT = uint256(keccak256('DummySimpleProposalEngineImpl_V1'));
    }

    function initialize(address oldImpl, bytes memory initData) external { }

    function getProposalExecutionStatus(bytes32 proposalId)
        external
        pure
        returns (ProposalExecutionStatus)
    {
        revert('not implemented 1');
    }

    function getLastExecutedProposalId() public view returns (uint256) {
        return _getStorage().lastExecutedProposalId;
    }

    function getFlagsForProposalId(uint256 proposalId) public view returns (uint256) {
        return _getStorage().proposalIdToFlags[proposalId];
    }

    function getNumExecutedProposals() public view returns (uint256) {
        return _getStorage().executedProposals;
    }

    function executeProposal(ExecuteProposalParams memory params)
        external returns (ProposalExecutionStatus)
    {
        uint256 proposalId = uint256(params.proposalId);
        _getStorage().lastExecutedProposalId = proposalId;
        _getStorage().proposalIdToFlags[proposalId] = uint256(params.flags);
        _getStorage().executedProposals += 1;
        return ProposalExecutionStatus.Complete;
    }

    // Retrieve the explicit storage bucket for the ProposalExecutionEngine logic.
    function _getStorage()
        private
        view
        returns (DummySimpleProposalEngineImplStorage storage stor)
    {
        uint256 slot = STORAGE_SLOT;
        assembly { stor.slot := slot }
    }
}
