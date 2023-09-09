// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { LibAddress } from "../utils/LibAddress.sol";
import { LibRawResult } from "../utils/LibRawResult.sol";
import { InitialETHCrowdfund } from "../crowdfund/InitialETHCrowdfund.sol";
import { Crowdfund } from "../crowdfund/Crowdfund.sol";

contract ContributionRouter {
    using LibRawResult for bytes;
    using LibAddress for address payable;

    event FeePerMintUpdated(uint96 oldFeePerMint, uint96 newFeePerMint);
    event ReceivedFees(address indexed sender, uint256 amount);
    event ClaimedFees(address indexed partyDao, address indexed recipient, uint256 amount);

    error OnlyOwner();

    /// @notice The address allowed to claim fees from the contract.
    address public immutable OWNER;

    /// @notice The amount of fees to pay to the DAO per mint.
    uint96 public feePerMint;

    constructor(address owner, uint96 initialFeePerMint) {
        OWNER = owner;
        feePerMint = initialFeePerMint;
    }

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert OnlyOwner();
        _;
    }

    /// @notice Set the fee per mint. Only the owner can call.
    /// @param newFeePerMint The new amount to set fee per mint to.
    function setFeePerMint(uint96 newFeePerMint) external onlyOwner {
        emit FeePerMintUpdated(feePerMint, newFeePerMint);

        feePerMint = newFeePerMint;
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
        uint256 feeAmount = feePerMint;
        address target;
        assembly {
            target := shr(96, calldataload(sub(calldatasize(), 0x14)))
        }
        if (msg.sig == InitialETHCrowdfund.batchContributeFor.selector) {
            uint256 numOfMints;
            assembly {
                // 228 is the offset of the length of `tokenIds` in the
                // calldata.
                numOfMints := calldataload(228)
            }
            feeAmount *= numOfMints;
        } else if (msg.sig == Crowdfund.batchContributeFor.selector) {
            uint256 numOfMints;
            assembly {
                // 164 is the offset of the length of `recipients` in the
                // calldata.
                numOfMints := calldataload(164)
            }
            feeAmount *= numOfMints;
        }
        (bool success, bytes memory res) = target.call{ value: msg.value - feeAmount }(msg.data);
        if (!success) res.rawRevert();

        emit ReceivedFees(msg.sender, feeAmount);
    }
}
