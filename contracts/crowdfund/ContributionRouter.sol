// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { LibAddress } from "../utils/LibAddress.sol";
import { LibRawResult } from "../utils/LibRawResult.sol";
import { InitialETHCrowdfund } from "../crowdfund/InitialETHCrowdfund.sol";

contract ContributionRouter {
    using LibRawResult for bytes;
    using LibAddress for address payable;

    event FeePerMintUpdated(uint96 oldFeePerMint, uint96 newFeePerMint);
    event ReceivedFees(address indexed sender, uint256 amount);
    event ClaimedFees(address indexed partyDao, address indexed recipient, uint256 amount);

    error OnlyOwner();

    /// @notice The address allowed to claim fees from the contract.
    address public immutable OWNER;

    struct Storage {
        uint96 feePerMint;
        address caller;
    }

    Storage private _storage;

    constructor(address owner, uint96 initialFeePerMint) {
        OWNER = owner;
        _storage.feePerMint = initialFeePerMint;
    }

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert OnlyOwner();
        _;
    }

    /// @notice Set the fee per mint. Only the owner can call.
    /// @param newFeePerMint The new amount to set fee per mint to.
    function setFeePerMint(uint96 newFeePerMint) external onlyOwner {
        emit FeePerMintUpdated(_storage.feePerMint, newFeePerMint);

        _storage.feePerMint = newFeePerMint;
    }

    /// @notice Claim fees from the contract. Only the owner can call.
    /// @param recipient The address to send the fees to.
    function claimFees(address payable recipient) external onlyOwner {
        uint256 balance = address(this).balance;

        recipient.transferEth(balance);

        emit ClaimedFees(msg.sender, recipient, balance);
    }

    /// @notice View function to get the `feePerMint` value.
    function feePerMint() external view returns (uint96) {
        return _storage.feePerMint;
    }

    /// @notice View function to get the most recent caller to the contract.
    function caller() external view returns (address) {
        return _storage.caller;
    }

    /// @notice Fallback function that forwards the call to the target contract
    ///         and keeps the fee amount. The target contract is expected to
    ///         be appended to the calldata.
    /// @dev Only initial contributions per address allow for setting the delegate.
    ///         Use the `delegate` function to set afterwards.
    fallback() external payable {
        uint256 feeAmount = _storage.feePerMint;
        _storage.caller = msg.sender;
        address target;
        assembly {
            target := shr(96, calldataload(sub(calldatasize(), 20)))
        }
        if (msg.sig == InitialETHCrowdfund.batchContributeFor.selector) {
            uint256 numOfMints;
            assembly {
                // 196 is the offset of the length of `tokenIds` in the
                // calldata.
                numOfMints := calldataload(196)
            }
            feeAmount *= numOfMints;
        }
        (bool success, bytes memory res) = target.call{ value: msg.value - feeAmount }(msg.data);
        if (!success) res.rawRevert();

        emit ReceivedFees(msg.sender, feeAmount);
    }

    // Revert for any vanilla ETH transfers.
    receive() external payable {
        revert();
    }
}
