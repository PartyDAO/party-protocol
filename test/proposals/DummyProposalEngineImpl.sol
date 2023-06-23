// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/IProposalExecutionEngine.sol";

contract DummyProposalEngineImpl is IProposalExecutionEngine {
    event TestInitializeCalled(address oldImpl, bytes32 initDataHash);

    address private immutable _IMPL;

    constructor() {
        _IMPL = address(this);
    }

    function initialize(address oldImpl, bytes memory initData) external {
        require(address(this) != _IMPL, "expected delegatecall");
        emit TestInitializeCalled(oldImpl, keccak256(initData));
    }

    function executeProposal(ExecuteProposalParams memory) external pure returns (bytes memory) {
        revert("not implemented");
    }

    function cancelProposal(uint256) external pure {
        revert("not implemented");
    }
}
