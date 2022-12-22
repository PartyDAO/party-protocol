// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/party/Party.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/utils/Proxy.sol";
import "../DummyERC20.sol";
import "../DummyERC1155.sol";
import "../DummyERC721.sol";
import "../TestUtils.sol";

contract PartyTest is Test, TestUtils {
    Party partyImpl;

    constructor() {
        Globals globals = new Globals(address(this));
        partyImpl = new Party(globals);
    }

    function test_cannotReinitialize() external {
        Party.PartyOpts memory opts;
        Party party = Party(
            payable(
                address(new Proxy(partyImpl, abi.encodeCall(Party.initialize, (opts, address(0)))))
            )
        );
        vm.expectRevert(abi.encodeWithSelector(Implementation.OnlyConstructorError.selector));
        party.initialize(opts, address(0));
    }
}
