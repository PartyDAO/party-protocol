// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { LibAddress } from "../utils/LibAddress.sol";
import { LibRawResult } from "../utils/LibRawResult.sol";

contract ContributionRouter {
    using LibRawResult for bytes;
    using LibAddress for address payable;

    event FeePerContributionUpdated(uint96 oldFeePerContribution, uint96 newFeePerContribution);
    event ReceivedFees(address indexed sender, uint256 amount);
    event ClaimedFees(address indexed partyDao, address indexed recipient, uint256 amount);

    error OnlyOwner();

    /// @notice The address allowed to claim fees from the contract.
    address public immutable OWNER;

    /// @notice The amount of fees to pay to the DAO per contribution.
    uint96 public feePerContribution;

    constructor(address owner, uint96 initialFeePerContribution) {
        OWNER = owner;
        feePerContribution = initialFeePerContribution;
    }

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert OnlyOwner();
        _;
    }

    /// @notice Set the fee per contribution. Only the owner can call.
    /// @param newFeePerContribution The new amount to set fee per contribution to.
    function setFeePerContribution(uint96 newFeePerContribution) external onlyOwner {
        emit FeePerContributionUpdated(feePerContribution, newFeePerContribution);

        feePerContribution = newFeePerContribution;
    }

    /// @notice Claim fees from the contract. Only the owner can call.
    /// @param recipient The address to send the fees to.
    function claimFees(address payable recipient) external onlyOwner {
        uint256 balance = address(this).balance;

        recipient.transferEth(balance);

        emit ClaimedFees(msg.sender, recipient, balance);
    }

    /// @notice Fallback function that forwards the call to the target contract
    ///         and keeps the fee amount. The target contract is expected to
    ///         be appended to the calldata.
    fallback() external payable {
        uint256 feeAmount = feePerContribution;
        address target;
        assembly {
            target := shr(96, calldataload(sub(calldatasize(), 0x14)))
        }
        (bool success, bytes memory res) = target.call{ value: msg.value - feeAmount }(msg.data);
        if (!success) res.rawRevert();

        emit ReceivedFees(msg.sender, feeAmount);
    }
}
