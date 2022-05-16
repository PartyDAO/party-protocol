// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./IGateKeeper.sol";
import "../tokens/IERC20.sol";

// A GateKeeper that implements a simple allow list (really a mapping) per gate.
contract GateKeeperERC20 is IGateKeeper {
    uint96 private _lastId;

    struct  TokenGate {
        address token;
        uint256 minimumBalance;
    }

    // gateId => (token, minimumBalance) tuple
    mapping(uint96 => bytes) _gateInfo;


    function isAllowed(
        address participant,
        bytes12 id,
        bytes memory /* userData */
    ) external view returns (bool) {
        TokenGate memory _gate = abi.decode(_gateInfo[uint96(id)], (TokenGate));
        //it has enogh tokens return true 
          //else return false
          if (IERC20(_gate.token).balanceOf(participant) >= _gate.minimumBalance) {
            return true;
        } else {
            return false;
        }
    }

    function createGate(address tokenAddress, uint256 minimumbalance)
        external
        returns (bytes12 id)
    {
        TokenGate  memory _gate = TokenGate(tokenAddress, minimumbalance);
        uint96 id_ = ++_lastId;
        id = bytes12(id);
        // store the struct(token, minimumbalance) it needs in the mapping
        _gateInfo[id_] = abi.encode(_gate);
    }
}