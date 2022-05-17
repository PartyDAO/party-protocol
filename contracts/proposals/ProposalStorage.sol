// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./IProposalExecutionEngine.sol";
import "../utils/LibRawResult.sol";
import "../tokens/IERC721.sol";

contract ProposalStorage {
    using LibRawResult for bytes;

    struct SharedProposalStorage {
        IProposalExecutionEngine engineImpl;
    }

    uint256 internal constant PROPOSAL_FLAG_UNANIMOUS = 0x1;
    uint256 private constant SHARED_STORAGE_SLOT = uint256(keccak256("ProposalStorage.SharedProposalStorage"));

    function _getProposalExecutionEngine()
        internal
        view
        returns (IProposalExecutionEngine impl)
    {
        return _getSharedProposalStorage().engineImpl;
    }

    function _setProposalExecutionEngine(IProposalExecutionEngine impl) internal {
        _getSharedProposalStorage().engineImpl = impl;
    }

    function _initProposalImpl(IProposalExecutionEngine impl, bytes memory initData)
        internal
    {
        SharedProposalStorage storage stor = _getSharedProposalStorage();
        IProposalExecutionEngine oldImpl = stor.engineImpl;
        stor.engineImpl = impl;
        (bool s, bytes memory r) = address(impl).delegatecall(
            // HACK: encodeCall() complains about converting the first parameter
            // from `bytes memory` to `bytes calldata` (wut), so use
            // encodeWithSelector().
            abi.encodeWithSelector(
                IProposalExecutionEngine.initialize.selector,
                abi.encode(oldImpl),
                initData
            )
        );
        if (!s) {
            r.rawRevert();
        }
    }

    function _getSharedProposalStorage()
        private
        view
        returns (SharedProposalStorage storage stor)
    {
        uint256 s = SHARED_STORAGE_SLOT;
        assembly { stor.slot := s }
    }

}
