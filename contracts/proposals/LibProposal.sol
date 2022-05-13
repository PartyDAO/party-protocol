// SPDX-License-Identifier: Apache-2.0
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
        IProposalExecutionEngine oldImpl = getProposalExecutionEngine();
        setProposalExecutionEngine(impl);
        (bool s, bytes memory r) = address(impl).delegatecall(
            // HACK: encodeCall() complains about converting the first parameter
            // from `bytes memory` to `bytes calldata` (wut), so use
            // encodeWithSelector().
            abi.encodeWithSelector(
                IProposalExecutionEngine.initialize.selector,
                abi.encode(oldImpl)
            )
        );
        if (!s) {
            r.rawRevert();
        }
    }
}
