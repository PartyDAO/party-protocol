// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./vendor/ENS.sol";

struct ENS {
    // Domain name (eg. "livingdead.partybid.eth")
    string name;
    // Node of the domain (eg. "partybid.eth"), hashed as specified in EIP-137
    bytes32 node;
    // Hash of the domain label (eg. `keccak256("livingdead")`)
    bytes32 label;
}

ENSRegistry constant ENS_REGISTRY = ENSRegistry(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);
ENSReverseRegistry constant REVERSE_REGISTRY = ENSReverseRegistry(
    0x084b1c3C81545d370f3634392De611CaaBFf8148
);
ENSResolver constant RESOLVER = ENSResolver(0x4976fb03C32e5B8cfe2b6cCB31c09Ba78EBaBa41);

// Namehash of "partybid.eth".
bytes32 constant DOMAIN_NODE = 0x739b60d02a3e52e8503ff5878da2ef95a296699ebfb38590f1affcdd513f2796;
// Owner of the "partybid.eth" domain.
address constant DOMAIN_OWNER = 0xF7f52Dd34bc21eDA08c0b804C7c1dbc48375820f;

/// @notice Base class for contracts to create and register an ENS subdomains for partybid.eth.
library LibENS {
    error DomainAlreadyRegistered(bytes32 node, address owner);
    error UnauthorizedForDomain(bytes32 node, address unauthorized);

    function createSubdomain(bytes32 label, address owner) internal returns (bytes32 subnode) {
        subnode = keccak256(abi.encodePacked(DOMAIN_NODE, label));

        // Ensure subdomain doesn't already exist.
        address prevOwner = ENS_REGISTRY.owner(subnode);
        if (prevOwner != address(0)) revert DomainAlreadyRegistered(subnode, prevOwner);

        ENS_REGISTRY.setSubnodeRecord(DOMAIN_NODE, label, owner, address(RESOLVER), 0);
    }

    function setSubdomainOwnership(bytes32 node, bytes32 label, address newOwner) internal {
        ENS_REGISTRY.setSubnodeOwner(node, label, newOwner);
    }

    function setDomainName(string memory name) internal {
        REVERSE_REGISTRY.setName(name);
    }

    function setAddress(bytes32 node, address addr) internal {
        // Set the resolver record of a subdomain.
        RESOLVER.setAddr(node, addr);
    }

    function setAuthorization(bytes32 node, address operator, bool isAuthorized) internal {
        RESOLVER.setAuthorisation(node, operator, isAuthorized);
    }

    function ensureIsAuthorized(bytes32 node, address operator) internal view {
        if (!RESOLVER.authorisations(node, ENS_REGISTRY.owner(node), operator))
            revert UnauthorizedForDomain(node, operator);
    }

    function isPartyBidSubdomain(bytes32 node) internal pure returns (bool) {
        return node == DOMAIN_NODE;
    }
}
