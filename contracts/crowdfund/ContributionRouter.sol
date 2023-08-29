// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import { Crowdfund } from "./Crowdfund.sol";
import { InitialETHCrowdfund } from "./InitialETHCrowdfund.sol";
import { LibAddress } from "../utils/LibAddress.sol";
import { IGlobals } from "../globals/IGlobals.sol";
import { LibGlobals } from "../globals/LibGlobals.sol";

contract ContributionRouter {
    event ReceivedFees(address indexed sender, uint256 amount);
    event ClaimedFees(address indexed partyDao, address indexed recipient);

    error OnlyPartyDaoError(address notDao, address partyDao);

    using LibAddress for address payable;

    // The `Globals` contract storing global configuration values. This contract
    // is immutable and it’s address will never change.
    IGlobals private immutable _GLOBALS;

    // Set the `Globals` contract.
    constructor(IGlobals globals) {
        _GLOBALS = globals;
    }

    modifier onlyPartyDao() {
        {
            address partyDao = _GLOBALS.getAddress(LibGlobals.GLOBAL_DAO_WALLET);
            if (msg.sender != partyDao) {
                revert OnlyPartyDaoError(msg.sender, partyDao);
            }
        }
        _;
    }

    /// @notice Contribute to an NFT crowdfund and pay an optional fee to the DAO.
    /// @param crowdfund The crowdfund to contribute to.
    /// @param delegate The address to delegate to for the governance phase.
    /// @param gateData Data to pass to the gatekeeper to prove eligibility.
    /// @param feeAmount The amount of ETH to pay to the DAO.
    function contributeToNFTCrowdfund(
        Crowdfund crowdfund,
        address delegate,
        bytes memory gateData,
        uint256 feeAmount
    ) external payable {
        // Contribute to the Party crowdfund, minus the fee. The fee will stay
        // in this contract until claimed by the DAO. Will revert if the fee is
        // greater than the contribution.
        crowdfund.contributeFor{ value: msg.value - feeAmount }(msg.sender, delegate, gateData);

        emit ReceivedFees(msg.sender, feeAmount);
    }

    /// @notice Contribute to an initial ETH crowdfund and pay an optional fee to the DAO.
    /// @param crowdfund The crowdfund to contribute to.
    /// @param tokenId The token ID to contribute to.
    /// @param delegate The address to delegate to for the governance phase.
    /// @param gateData Data to pass to the gatekeeper to prove eligibility.
    /// @param feeAmount The amount of ETH to pay to the DAO.
    function contributeToInitialETHCrowdfund(
        InitialETHCrowdfund crowdfund,
        uint256 tokenId,
        address delegate,
        bytes memory gateData,
        uint256 feeAmount
    ) external payable {
        // Contribute to the Party crowdfund, minus the fee. The fee will stay
        // in this contract until claimed by the DAO. Will revert if the fee is
        // greater than the contribution.
        crowdfund.contributeFor{ value: msg.value - feeAmount }(
            tokenId,
            payable(msg.sender),
            delegate,
            gateData
        );

        emit ReceivedFees(msg.sender, feeAmount);
    }

    /// @notice Claim fees from the contract as the DAO.
    /// @param recipient The address to send the fees to.
    function claimFees(address payable recipient) external onlyPartyDao {
        recipient.transferEth(address(this).balance);

        emit ClaimedFees(msg.sender, recipient);
    }

    receive() external payable {}
}
