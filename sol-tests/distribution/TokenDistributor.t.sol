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
  DummyTokenDistributorParty dummyParty1 = new DummyTokenDistributorParty();
  DummyTokenDistributorParty dummyParty2 = new DummyTokenDistributorParty();
  
  function setUp() public {
    vm.deal(ADMIN_ADDRESS, 500 ether);
    globals = new Globals(ADMIN_ADDRESS);
    vm.prank(ADMIN_ADDRESS);
    globals.setAddress(LibGlobals.GLOBAL_DAO_WALLET, ADMIN_ADDRESS);
    distributor = new TokenDistributor(globals);
  }
  
  function testEthDistributionSimple() public {
    TokenDistributor.DistributionInfo memory ds = _createEthDistribution(dummyParty1, 0.025 ether, 1.337 ether);
    
    assertEq(DISTRIBUTION_ADDRESS.balance, 0);
    assert(!distributor.hasPartyDaoClaimed(dummyParty1, ds.distributionId));
    vm.prank(ADMIN_ADDRESS);
    distributor.partyDaoClaim(ds, DISTRIBUTION_ADDRESS);
    assertEq(DISTRIBUTION_ADDRESS.balance, 0.033425 ether);
    assert(distributor.hasPartyDaoClaimed(dummyParty1, ds.distributionId));

    _createDummyToken(dummyParty1, address(3), 3, 0.34 ether);
    _createDummyToken(dummyParty1, address(4), 4, 0.66 ether);
    
    assert(!distributor.hasTokenIdClaimed(dummyParty1, 3, ds.distributionId));
    uint256 ethGained1 = _claimAndReturnDiff(ds, address(3), 3, address(3));
    assert(distributor.hasTokenIdClaimed(dummyParty1, 3, ds.distributionId));
    _assertEthApprox(ethGained1, 0.4432155 ether);
    
    uint256 ethGained2 = _claimAndReturnDiff(ds, address(4), 4, address(4));
    _assertEthApprox(ethGained2, 0.8603595 ether);
    
    assertEq(address(distributor).balance, 0);
  }

  function testMultiplePartyDistributions() public {
    vm.prank(ADMIN_ADDRESS);
    globals.setUint256(LibGlobals.GLOBAL_DAO_DISTRIBUTION_SPLIT, 0.05 ether); // 5%

    // distribution 1
    payable(address(distributor)).transfer(0.1 ether);
    vm.prank(address(dummyParty1)); // must create from party
    TokenDistributor.DistributionInfo memory ds1 = distributor.createDistribution(ETH_TOKEN);
    _createDummyToken(dummyParty1, address(1), 1337, 0.7 ether);
    _createDummyToken(dummyParty1, address(2), 1338, 0.3 ether);
    // distribution 2
    payable(address(distributor)).transfer(0.25 ether);
    vm.prank(address(dummyParty1)); // must create from party
    TokenDistributor.DistributionInfo memory ds2 = distributor.createDistribution(ETH_TOKEN);
    _createDummyToken(dummyParty2, address(1), 1337, 0.33 ether);
    _createDummyToken(dummyParty2, address(3), 1338, 0.66 ether);
    // distribution 3

    // ****** DISTRIBUTION 1 *****
    // receive for id 1
    _assertEthApprox(
      _claimAndReturnDiff(ds1, address(1), 1337, address(1)),
      0.0665 ether
    );
    assertEq(
      _daoClaimEthAndReturnDiff(ds1),
      0.005 ether
    );

    // user cant claim again
    vm.expectRevert(
          abi.encodeWithSignature("DistributionAlreadyClaimedByTokenError(uint256,uint256)", 1, 1337)
    );
    vm.prank(address(1));
    distributor.claim(ds1, 1337, payable(address(1)));

    // partydao cant claim again
    vm.expectRevert(
          abi.encodeWithSignature("DistributionAlreadyClaimedByPartyDaoError(uint256)", 1)
    );
    vm.prank(ADMIN_ADDRESS);
    distributor.partyDaoClaim(ds1, DISTRIBUTION_ADDRESS);

    // ****** DISTRIBUTION 2 *****
    // _assertEthApprox(
    //   _claimAndReturnDiff(ds2, address(1), 1337, address(1)),
    //   0.004125 ether
    // );


  }

  // TODO: ensure claiming one id doesnt claim another
  
  
  // TODO: emergency fns?
  
  // TODO: ERC 20

  
  // TODO: what happens if called with zero amount?
  

  // to handle weird rounding error
  function _assertEthApprox(uint256 givenAmount, uint256 expectedAmount) private {
    assertApproxEqAbs(givenAmount, expectedAmount, 0.0000000000001 ether);
  }

  function _daoClaimEthAndReturnDiff(
    TokenDistributor.DistributionInfo memory di
  ) private returns (uint256) {
      vm.prank(ADMIN_ADDRESS);
      uint256 beforeBal = DISTRIBUTION_ADDRESS.balance;
      distributor.partyDaoClaim(di, DISTRIBUTION_ADDRESS);
      uint256 afterBal = DISTRIBUTION_ADDRESS.balance;
      return afterBal - beforeBal;
  }

  function _createDummyToken(
    DummyTokenDistributorParty dummyParty,
    address user,
    uint256 tokenId,
    uint256 shareAmount
  ) public {
    vm.deal(user, 100 ether);
    dummyParty.setOwner(user, tokenId);
    dummyParty.setShare(tokenId, shareAmount);
  }
  
  function _createEthDistribution(
    DummyTokenDistributorParty dummyParty,
    uint256 globalSplit,
    uint256 ethAmount
  ) private returns (TokenDistributor.DistributionInfo memory) {
    vm.prank(ADMIN_ADDRESS);
    globals.setUint256(LibGlobals.GLOBAL_DAO_DISTRIBUTION_SPLIT, globalSplit);

    payable(address(distributor)).transfer(ethAmount);
    vm.prank(address(dummyParty)); // must create from party
    return distributor.createDistribution(ETH_TOKEN);
  }

  function _claimAndReturnDiff(
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