// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./IProposalExecutionEngine.sol";
import "../utils/LibRawResult.sol";
import "../tokens/IERC721.sol";

contract ProposalStorage {
    using LibRawResult for bytes;

    struct SharedProposalStorage {
        IProposalExecutionEngine engineImpl;
        bytes32 preciousListHash;
    }

    error MismatchedPreciousListLengths();

    uint256 internal constant PROPOSAL_FLAG_UNANIMOUS = 0x1;
    uint256 private constant SHARED_STORAGE_SLOT =
        uint256(keccak256("ProposalStorage.SharedProposalStorage"));

    function _getProposalExecutionEngine()
        internal
        view
        returns (IProposalExecutionEngine impl)
    {
        return _getSharedProposalStorage().engineImpl;
    }

    function _getPreciousListHash() internal view returns (bytes32) {
        return _getSharedProposalStorage().preciousListHash;
    }

    function _setProposalExecutionEngine(IProposalExecutionEngine impl) internal {
        _getSharedProposalStorage().engineImpl = impl;
    }

    function _setPreciousList(
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) internal {
        if (preciousTokens.length != preciousTokenIds.length) {
            revert MismatchedPreciousListLengths();
        }
        _getSharedProposalStorage().preciousListHash = _hashPreciousList(
            preciousTokens,
            preciousTokenIds
        );
    }

    function _initProposalImpl(IProposalExecutionEngine impl, bytes memory initData)
        internal
    {
        SharedProposalStorage storage stor = _getSharedProposalStorage();
        IProposalExecutionEngine oldImpl = stor.engineImpl;
        stor.engineImpl = impl;
        (bool s, bytes memory r) = address(impl).delegatecall(
            abi.encodeCall(
                IProposalExecutionEngine.initialize,
                (address(oldImpl), initData)
            )
        );
        if (!s) {
            r.rawRevert();
        }
    }

    function _isPreciousListCorrect(
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) internal view returns (bool) {
        return
            _getPreciousListHash() ==
            _hashPreciousList(preciousTokens, preciousTokenIds);
    }

    function _hashPreciousList(
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) internal pure returns (bytes32 h) {
        assembly {
            mstore(
                0x00,
                keccak256(
                    add(preciousTokens, 0x20),
                    mul(mload(preciousTokens), 0x20)
                )
            )
            mstore(
                0x20,
                keccak256(
                    add(preciousTokenIds, 0x20),
                    mul(mload(preciousTokenIds), 0x20)
                )
            )
            h := keccak256(0x00, 0x40)
        }
    }

    function _getSharedProposalStorage()
        private
        pure
        returns (SharedProposalStorage storage stor)
    {
        uint256 s = SHARED_STORAGE_SLOT;
        assembly { stor.slot := s }
    }

}
