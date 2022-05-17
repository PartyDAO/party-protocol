// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/distribution/TokenDistributor.sol";
import "../../contracts/distribution/ITokenDistributorParty.sol";
import "../../contracts/globals/Globals.sol";
import "../TestUtils.sol";
import "./DummyTokenDistributorParty.sol";

contract TokenDistributorTest is Test, TestUtils {
  address immutable ADMIN_ADDRESS = address(1);
  address payable immutable DISTRIBUTION_ADDRESS = payable(address(2));
  IERC20 immutable ETH_TOKEN = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
  Globals globals;
  TokenDistributor distributor;
  DummyTokenDistributorParty dummyParty = new DummyTokenDistributorParty();
  
  function setUp() public {
    vm.deal(ADMIN_ADDRESS, 500 ether);
    globals = new Globals(ADMIN_ADDRESS);
    vm.prank(ADMIN_ADDRESS);
    globals.setAddress(LibGlobals.GLOBAL_DAO_WALLET, ADMIN_ADDRESS);
    distributor = new TokenDistributor(globals);
  }
  
  function testEthDistributionSimple() public {
    vm.prank(ADMIN_ADDRESS);
    globals.setUint256(LibGlobals.GLOBAL_DAO_DISTRIBUTION_SPLIT, 0.025 ether); // 2.5%

    payable(address(distributor)).transfer(1.337 ether);
    vm.prank(address(dummyParty)); // must create from party
    TokenDistributor.DistributionInfo memory ds = distributor.createDistribution(ETH_TOKEN);
    
    assertEq(DISTRIBUTION_ADDRESS.balance, 0);
    vm.prank(ADMIN_ADDRESS);
    distributor.partyDaoClaim(ds, DISTRIBUTION_ADDRESS);
    assertEq(DISTRIBUTION_ADDRESS.balance, 0.033425 ether);
    
    vm.deal(address(3), 100 ether);
    dummyParty.setOwner(address(3), 3);
    dummyParty.setShare(3, 0.34 ether);
    
    vm.deal(address(4), 100 ether);
    dummyParty.setOwner(address(4), 4);
    dummyParty.setShare(4, 0.66 ether);
    
    uint256 ethGained1 = _getEthGained(ds, address(3), 3, address(3));
    assertApproxEqAbs(ethGained1, 0.4432155 ether, 0.0000000000001 ether); // weird rounding error
    
    uint256 ethGained2 = _getEthGained(ds, address(4), 4, address(4));
    assertApproxEqAbs(ethGained2, 0.8603595 ether, 0.0000000000001 ether); // weird rounding error
    
    assertEq(address(distributor).balance, 0);
  }
  
  // TODO: tokenDistribution info?
  
  // TODO: emergency fns?
  
  // TODO: ERC 20
  
  // TODO: multiple distributions
  
  // TODO: what happens if called with zero amount?
  
  // TODO: check that cant claim multiple
  
  function _getEthGained(
    TokenDistributor.DistributionInfo memory ds,
    address prankAs,
    uint256 tokenId,
    address recipient
  ) private returns (uint256) {
    uint256 initialEth = recipient.balance;
    uint256 startGas = gasleft();
    vm.prank(prankAs);
    distributor.claim(ds, tokenId, payable(recipient));
    uint256 endGas = gasleft();
    uint256 gasUsed = startGas - endGas;
    uint256 newBalance = recipient.balance;
    uint256 ethGained = newBalance - (initialEth + gasUsed);
    return ethGained;
  }
}