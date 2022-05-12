// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// import "./IGateKeeper.sol";
import "../tokens/IERC20.sol";

//able to flex to different types of gatekeeping logic
//bytes calldata encoded 
//based on type of gatekeeping
//decode the data you expect
//which should be token address and minimum balance

/**
 * @notice defines whether or not a user can access party
 */
contract GateKeeper {

    address tokenAddress;
    uint256 minimumBalance;

  constructor (bytes memory _callData) {
    
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
        // uint256 _minimumBalance,
        // address _tokenAddress,
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
