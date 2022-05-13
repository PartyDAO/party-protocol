// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./IGateKeeper.sol";
import "../tokens/IERC20.sol";

// A GateKeeper that implements a simple allow list (really a mapping) per gate.
contract GateKeeperERC20 is IGateKeeper {
    uint96 private _lastId;

    struct TokenGate {
        address token;
        uint256 minimumBalance;
    }

    // gateId => (token, minimumBalance) tuple
    mapping(uint96 => TokenGate) _isAllowedByGateId;

    // gate ID -> contributor -> isAllowed
    // mapping (uint96 => mapping (address => bool)) _isAllowedByGateId;

    function isAllowed(
        address participant,
        bytes12 id,
        bytes memory /* userData */
    ) external view returns (bool) {
        // logic goes here
        //it has enogh tokens return true 
        //else return false
    }

    function createGate(bytes calldata _arbitraryGateData)
        external
        returns (bytes12 id)
    {
        // decode the arbitrary gate data based on the types it expects --> tokenAddress, minimumAmount
        TokenGate memory tokengate = abi.decode(
            _arbitraryGateData,
            (TokenGate)
        );
        uint96 id_ = ++_lastId;
        id = bytes12(id);
        // store the information it needs in the mapping
        _isAllowedByGateId[id_] = [tokengate];
    }
}