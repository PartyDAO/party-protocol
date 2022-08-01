// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "./Proxy.sol";

interface ICreate2ProxyDeployer {
    function create2Implementation() external view returns (Implementation);
    function create2InitCallData() external view returns (bytes memory);
}

// Proxy that works with create2 deterministic addresses.
contract Create2Proxy is Proxy {
    constructor()
        payable
        public
        Proxy(
            ICreate2ProxyDeployer(msg.sender).create2Implementation(),
            ICreate2ProxyDeployer(msg.sender).create2InitCallData()
        )
    {}
}
