// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../tokens/IERC20.sol";

/**
 * @notice defines whether or not a user can access party
 */
contract GateKeeper {

    address tokenAddress;
    uint256 minimumBalance;
  
    //encoded calldata
    constructor (bytes memory _callData) {
      //TODO decode the calldata
      //TODO assign it to tokenAddress, minimumBalance
    }

    /**
     * @notice defines whether or not a user can access party
     * @param _participant contributor address
     * @param _id user id
     * @param _userData optional arb data that verifies proof of membership
     * @return bool true of false depeing if the user has enough tokens
     */
    function isAllowed(
        address _participant,
        bytes12 _id,
        bytes memory _userData
    ) external view returns (bool) {
        if (IERC20(tokenAddress).balanceOf(_participant) >= minimumBalance) {
            return true;
        } else {
            return false;
        }
    }
}
