// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/IProposalExecutionEngine.sol";

contract DummySimpleProposalEngineImpl is IProposalExecutionEngine {

    mapping (uint256 => bool) proposalExecuted;

    constructor() {}

    function initialize(address oldImpl, bytes memory initData) external { }

    function getProposalExecutionStatus(bytes32 proposalId)
        external
        view
        returns (ProposalExecutionStatus)
    {
        revert('not implemented 1');
    }

    function executeProposal(ExecuteProposalParams memory params)
        external returns (ProposalExecutionStatus)
    {
       proposalExecuted[uint256(params.proposalId)] = true;
       return ProposalExecutionStatus.Complete;
    }
}
