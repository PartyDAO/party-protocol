// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

library LibProposal {
    uint256 internal constant PROPOSAL_ENGINE_SLOT = uint256(keccak256("proposalExectionEngine"));
    uint256 internal constant PROPOSAL_FLAG_UNANIMOUS = 0x1;

    function getProposalExecutionEngine()
        internal
        view
        returns (IProposalExecutionEngine impl)
    {
        uint256 slot = PROPOSAL_ENGINE_SLOT;
        assembly { impl := and(sload(slot), 0xffffffffffffffffffffffffffffffffffffffff) }
    }

    function setProposalExecutionEngine(IProposalExecutionEngine impl) internal {
        uint256 slot = PROPOSAL_ENGINE_SLOT;
        assembly { sstore(slot, and(impl, 0xffffffffffffffffffffffffffffffffffffffff)) }
    }

    function initProposalImpl(IProposalExecutionEngine proposalEngine)
        internal
    {
        setProposalExecutionEngine(impl);
        (bool s, bytes memory r) = address(proposalEngine).delegatecall(abi.encodeCall(
            IProposalExecutionEngine.initialize,
            getProposalExecutionEngine(),
        ));
        if (!s) {
            r.rawRevert();
        }
    }
}
