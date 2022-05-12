// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "./IProposalExecutionEngine.sol";
import "../utils/LibRawResult.sol";

library LibProposal {
    using LibRawResult for bytes;

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

    function initProposalImpl(IProposalExecutionEngine impl)
        internal
    {
        setProposalExecutionEngine(impl);
        (bool s, bytes memory r) = address(impl).delegatecall(abi.encodeCall(
            IProposalExecutionEngine.initialize,
            address(getProposalExecutionEngine())
        ));
        if (!s) {
            r.rawRevert();
        }
    }
}
