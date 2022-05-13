// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../tokens/IERC721.sol";

import "./LibProposal.sol";
import "./IProposalExecutionEngine.sol";

// Implements arbitrary call proposals.
contract ArbitraryCallsProposal {
    struct ArbitraryCall {
        address payable target;
        uint256 value;
        bytes data;
        // If true, the call is allowed to fail.
        bool optional;
        // Hash of the successful return data of the call.
        // If 0x0, no return data checking will occur for this call.
        bytes32 expectedResultHash;
    }

    error PreciousLostError();
    error CallProhibitedError(address target, bytes data);
    error ArbitraryCallFailedError(bytes revertData);
    error UnexpectedCallResultHashError(uint256 idx, bytes32 resultHash, bytes32 expectedResultHash);
    error NotEnoughEthAttachedError(uint256 callValue, uint256 ethAvailable);
    error InvalidApproveCallDataError(bytes callData);

    function _executeArbitraryCalls(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    )
        internal
    {
        (ArbitraryCall[] memory calls) = abi.decode(params.proposalData, (ArbitraryCall[]));
        bool hadPrecious = _getHasPrecious(params.preciousToken, params.preciousTokenId);
        uint256 ethAvailable = msg.value;
        for (uint256 i = 0; i < calls.length; ++i) {
            _executeSingleArbitraryCall(
                i,
                calls[i],
                params.preciousToken,
                params.preciousTokenId,
                params.flags,
                ethAvailable
            );
            ethAvailable -= calls[i].value;
        }
        // If we had the precious beforehand, check that we still have it now.
        if (hadPrecious) {
            if (!_getHasPrecious(params.preciousToken, params.preciousTokenId)) {
                revert PreciousLostError();
            }
        }
    }

    function _executeSingleArbitraryCall(
        uint256 idx,
        ArbitraryCall memory call,
        IERC721 preciousToken,
        uint256 preciousTokenId,
        uint256 flags,
        uint256 ethAvailable
    )
        private
    {
        if (!_isCallProhibited(call, preciousToken, preciousTokenId, flags)) {
            revert CallProhibitedError(call.target, call.data);
        }
        if (ethAvailable < call.value) {
            revert NotEnoughEthAttachedError(call.value, ethAvailable);
        }
        (bool s, bytes memory r) = call.target.call{ value: call.value }(call.data);
        if (!s) {
            if (!call.optional) {
                revert ArbitraryCallFailedError(r);
            }
        } else {
            if (call.expectedResultHash != bytes32(0)) {
                bytes32 resultHash = keccak256(r);
                if (resultHash != call.expectedResultHash) {
                    revert UnexpectedCallResultHashError(
                        idx,
                        resultHash,
                        call.expectedResultHash
                    );
                }
            }
        }
    }

    // Do we possess the precious?
    function _getHasPrecious(IERC721 preciousToken, uint256 preciousTokenId)
        private
        view
        returns (bool hasPrecious)
    {
        hasPrecious = preciousToken.ownerOf(preciousTokenId) == address(this);
    }

    function _isCallProhibited(
        ArbitraryCall memory call,
        IERC721 preciousToken,
        uint256 preciousTokenId,
        uint256 flags
    )
        private
        view
        returns (bool isProhibited)
    {
        // Cannot call ourselves.
        if (call.target == address(this)) {
            return true;
        }
        bool isUnanimous = flags & LibProposal.PROPOSAL_FLAG_UNANIMOUS
            == LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        // Unanimous proposals can call any function.
        if (!isUnanimous && (call.data.length >= 4 && call.target == address(preciousToken))) {
            bytes4 selector;
            {
                bytes memory callData = call.data;
                assembly { selector := and(mload(add(callData, 4)), 0xffffffff) }
            }
            // Cannot call approve() or setApprovalForAll() on the precious
            // unless it's to revoke approvals.
            if (selector == IERC721.approve.selector) {
                (address op, uint256 tokenId) = _decodeApproveCallDataArgs(call.data);
                if (tokenId == preciousTokenId) {
                    return op != address(0);
                }
                return true;
            } else if (selector == IERC721.setApprovalForAll.selector) {
                (, bool isApproved) = _decodeSetApprovalForAllCallDataArgs(call.data);
                return isApproved;
            }
        }
        // TODO: Do we need to block TokenDistributor contract too?
        return true;
    }

    function _decodeApproveCallDataArgs(bytes memory callData)
        private
        pure
        returns (address operator, uint256 tokenId)
    {
        if (callData.length < 68) {
            revert InvalidApproveCallDataError(callData);
        }
        assembly {
            operator := and(
                mload(add(callData, 36)),
                0xffffffffffffffffffffffffffffffffffffffff
            )
            tokenId := mload(add(callData, 68))
        }
    }

    function _decodeSetApprovalForAllCallDataArgs(bytes memory callData)
        private
        pure
        returns (address operator, bool isApproved)
    {
        if (callData.length < 68) {
            revert InvalidApproveCallDataError(callData);
        }
        assembly {
            operator := and(
                mload(add(callData, 36)),
                0xffffffffffffffffffffffffffffffffffffffff
            )
            isApproved := not(iszero(mload(add(callData, 68))))
        }
    }
}
