// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// import "./IGateKeeper.sol"; 
import "../tokens/IERC20.sol";

 /**
 * @notice defines whether or not a user can access party
 */
contract GateKeeper {


   /**
   * @notice defines whether or not a user can access party
   * @param  participant contributor address
   * @param minimumBalance minimum balance allowed for participation
   * @param tokenAddress ERC-20 token address 
   * @param id user id
   * @param userData optional arb data that verifies proof of membership 
   * @return bool true of false depeing if the user has enough tokens 
   */
    function isAllowed(
     address participant,
     uint256 minimumBalance,
     address tokenAddress,
     bytes12 id,
     bytes memory userData
    ) external view returns (bool) {
        if (IERC20(tokenAddress).balanceOf(participant) >= minimumBalance) {
            return true;
        } else {
            return false;
        }
    }
}