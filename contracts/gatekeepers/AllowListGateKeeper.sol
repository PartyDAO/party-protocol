// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./IGateKeeper.sol";

// A GateKeeper that implements a simple allow list (really a mapping) per gate.
contract AllowListGateKeeper is IGateKeeper {

    uint96 private _lastId;
    // gate ID -> contributor -> isAllowed
    mapping (uint96 => mapping (address => bool)) _isAllowedByGateId;

    function isAllowed(
        address participant,
        bytes12 id,
        bytes memory /* userData */
    )
        external
        view
        returns (bool)
    {
        return _isAllowedByGateId[uint96(id)][participant];
    }

    function createGate(address[] memory members)
        external
        returns (bytes12 id)
    {
        uint96 id_ = ++_lastId;
        id = bytes12(id_);
        for (uint256 i = 0; i < members.length; ++i) {
            _isAllowedByGateId[id_][members[i]] = true;
        }
    }
}
