// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../tokens/IERC721.sol";
import "../tokens/IERC721Receiver.sol";
import "../tokens/ERC1155Receiver.sol";
import "../utils/LibSafeERC721.sol";
import "../utils/LibAddress.sol";
import "../vendor/markets/IZoraAuctionHouse.sol";
import "./vendor/IOpenseaExchange.sol";

import "./LibProposal.sol";
import "./IProposalExecutionEngine.sol";

// Implements arbitrary call proposals. Inherited by the `ProposalExecutionEngine`.
// This contract will be delegatecall'ed into by `Party` proxy instances.
contract ArbitraryCallsProposal {
    using LibSafeERC721 for IERC721;
    using LibAddress for address payable;

    struct ArbitraryCall {
        // The call target.
        address payable target;
        // Amount of ETH to attach to the call.
        uint256 value;
        // Calldata.
        bytes data;
        // Hash of the successful return data of the call.
        // If 0x0, no return data checking will occur for this call.
        bytes32 expectedResultHash;
    }

    error PreciousLostError(IERC721 token, uint256 tokenId);
    error CallProhibitedError(address target, bytes data);
    error ArbitraryCallFailedError(bytes revertData);
    error UnexpectedCallResultHashError(
        uint256 idx,
        bytes32 resultHash,
        bytes32 expectedResultHash
    );
    error NotEnoughEthAttachedError(uint256 callValue, uint256 ethAvailable);
    error InvalidApprovalCallLength(uint256 callDataLength);

    event ArbitraryCallExecuted(uint256 proposalId, uint256 idx, uint256 count);

    IZoraAuctionHouse private immutable _ZORA;

    constructor(IZoraAuctionHouse zora) {
        _ZORA = zora;
    }

    function _executeArbitraryCalls(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) internal returns (bytes memory nextProgressData) {
        // Get the calls to execute.
        ArbitraryCall[] memory calls = abi.decode(params.proposalData, (ArbitraryCall[]));
        // Check whether the proposal was unanimously passed.
        bool isUnanimous = params.flags & LibProposal.PROPOSAL_FLAG_UNANIMOUS ==
            LibProposal.PROPOSAL_FLAG_UNANIMOUS;
        // If not unanimous, keep track of which preciouses we had before the calls
        // so we can check that we still have them later.
        bool[] memory hadPreciouses = new bool[](params.preciousTokenIds.length);
        if (!isUnanimous) {
            for (uint256 i; i < hadPreciouses.length; ++i) {
                hadPreciouses[i] = _getHasPrecious(
                    params.preciousTokens[i],
                    params.preciousTokenIds[i]
                );
            }
        }
        // Can only forward ETH attached to the call.
        uint256 ethAvailable = msg.value;
        for (uint256 i; i < calls.length; ++i) {
            // Execute an arbitrary call.
            _executeSingleArbitraryCall(
                i,
                calls,
                params.preciousTokens,
                params.preciousTokenIds,
                isUnanimous,
                ethAvailable
            );
            // Update the amount of ETH available for the subsequent calls.
            ethAvailable -= calls[i].value;
            emit ArbitraryCallExecuted(params.proposalId, i, calls.length);
        }
        // If not a unanimous vote and we had a precious beforehand,
        // ensure that we still have it now.
        if (!isUnanimous) {
            for (uint256 i; i < hadPreciouses.length; ++i) {
                if (hadPreciouses[i]) {
                    if (!_getHasPrecious(params.preciousTokens[i], params.preciousTokenIds[i])) {
                        revert PreciousLostError(
                            params.preciousTokens[i],
                            params.preciousTokenIds[i]
                        );
                    }
                }
            }
        }
        // Refund leftover ETH.
        if (ethAvailable > 0) {
            payable(msg.sender).transferEth(ethAvailable);
        }
        // No next step, so no progressData.
        return "";
    }

    function _executeSingleArbitraryCall(
        uint256 idx,
        ArbitraryCall[] memory calls,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        bool isUnanimous,
        uint256 ethAvailable
    ) private {
        ArbitraryCall memory call = calls[idx];
        // Check that the call is not prohibited.
        if (
            !_isCallAllowed(call, isUnanimous, idx, calls.length, preciousTokens, preciousTokenIds)
        ) {
            revert CallProhibitedError(call.target, call.data);
        }
        // Check that we have enough ETH to execute the call.
        if (ethAvailable < call.value) {
            revert NotEnoughEthAttachedError(call.value, ethAvailable);
        }
        // Execute the call.
        (bool s, bytes memory r) = call.target.call{ value: call.value }(call.data);
        if (!s) {
            // Call failed. If not optional, revert.
            revert ArbitraryCallFailedError(r);
        } else {
            // Call succeeded.
            // If we have a nonzero expectedResultHash, check that the result data
            // from the call has a matching hash.
            if (call.expectedResultHash != bytes32(0)) {
                bytes32 resultHash = keccak256(r);
                if (resultHash != call.expectedResultHash) {
                    revert UnexpectedCallResultHashError(idx, resultHash, call.expectedResultHash);
                }
            }
        }
    }

    // Do we possess the precious?
    function _getHasPrecious(
        IERC721 preciousToken,
        uint256 preciousTokenId
    ) private view returns (bool hasPrecious) {
        hasPrecious = preciousToken.safeOwnerOf(preciousTokenId) == address(this);
    }

    function _isCallAllowed(
        ArbitraryCall memory call,
        bool isUnanimous,
        uint256 callIndex,
        uint256 callsCount,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    ) private view returns (bool isAllowed) {
        // Cannot call ourselves.
        if (call.target == address(this)) {
            return false;
        }
        if (call.data.length >= 4) {
            // Get the function selector of the call (first 4 bytes of calldata).
            bytes4 selector;
            {
                bytes memory callData = call.data;
                assembly {
                    selector := and(
                        mload(add(callData, 32)),
                        0xffffffff00000000000000000000000000000000000000000000000000000000
                    )
                }
            }
            // Non-unanimous proposals restrict what ways some functions can be
            // called on a precious token.
            if (!isUnanimous) {
                // Cannot call `approve()` or `setApprovalForAll()` on the precious
                // unless it's to revoke approvals.
                if (selector == IERC721.approve.selector) {
                    // Can only call `approve()` on the precious if the operator is null.
                    (address op, uint256 tokenId) = _decodeApproveCallDataArgs(call.data);
                    if (op != address(0)) {
                        return
                            !LibProposal.isTokenIdPrecious(
                                IERC721(call.target),
                                tokenId,
                                preciousTokens,
                                preciousTokenIds
                            );
                    }
                    // Can only call `setApprovalForAll()` on the precious if
                    // toggling off.
                } else if (selector == IERC721.setApprovalForAll.selector) {
                    (, bool isApproved) = _decodeSetApprovalForAllCallDataArgs(call.data);
                    if (isApproved) {
                        return !LibProposal.isTokenPrecious(IERC721(call.target), preciousTokens);
                    }
                    // Can only call cancelAuction on the zora AH if it's the last call
                    // in the sequence.
                } else if (selector == IZoraAuctionHouse.cancelAuction.selector) {
                    if (call.target == address(_ZORA)) {
                        return callIndex + 1 == callsCount;
                    }
                }
            }
            // Can never call receive hooks on any target.
            if (
                selector == IERC721Receiver.onERC721Received.selector ||
                selector == ERC1155TokenReceiverBase.onERC1155Received.selector ||
                selector == ERC1155TokenReceiverBase.onERC1155BatchReceived.selector
            ) {
                return false;
            }
            // Disallow calling `validate()` on Seaport.
            if (selector == IOpenseaExchange.validate.selector) {
                return false;
            }
        }
        // All other calls are allowed.
        return true;
    }

    // Get the `operator` and `tokenId` from the `approve()` call data.
    function _decodeApproveCallDataArgs(
        bytes memory callData
    ) private pure returns (address operator, uint256 tokenId) {
        if (callData.length < 68) {
            revert InvalidApprovalCallLength(callData.length);
        }
        assembly {
            operator := and(mload(add(callData, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            tokenId := mload(add(callData, 68))
        }
    }

    // Get the `operator` and `tokenId` from the `setApprovalForAll()` call data.
    function _decodeSetApprovalForAllCallDataArgs(
        bytes memory callData
    ) private pure returns (address operator, bool isApproved) {
        if (callData.length < 68) {
            revert InvalidApprovalCallLength(callData.length);
        }
        assembly {
            operator := and(mload(add(callData, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            isApproved := xor(iszero(mload(add(callData, 68))), 1)
        }
    }
}
