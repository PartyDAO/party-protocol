// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract GovernableERC20 is ERC20, ERC20Permit, ERC20Votes {
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        address _receiver
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        _mint(_receiver, _totalSupply);
    }

    // Default to self-delegation if no delegate is set. This enables snapshots
    // to work as expected, otherwise when transferring votes to undelegated addresses
    // the votes would not be moved (see `Votes._moveDelegateVotes`).
    function delegates(address account) public view override returns (address) {
        address delegate = super.delegates(account);
        return delegate == address(0) ? account : delegate;
    }

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
