// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "../contracts/globals/Globals.sol";
import "../contracts/globals/LibGlobals.sol";

contract GlobalsAdmin is Test {
  Globals public globals;

  constructor() {
    globals = new Globals(address(this));
    vm.deal(address(this), 100 ether);
  }

  function setPartyImpl(address partyImplAddress) public {
    globals.setAddress(LibGlobals.GLOBAL_PARTY_IMPL, partyImplAddress);
  }

  function setProposalEng(address proposalEngAddress) public {
    globals.setAddress(LibGlobals.GLOBAL_PROPOSAL_ENGINE_IMPL, proposalEngAddress);
  }
}