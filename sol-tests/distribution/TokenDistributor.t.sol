// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/distribution/TokenDistributor.sol";
import "../../contracts/distribution/ITokenDistributorParty.sol";
import "../../contracts/globals/Globals.sol";

import "../TestUtils.sol";
import "../DummyERC20.sol";
import "./DummyTokenDistributorParty.sol";

contract TokenDistributorTest is Test, TestUtils {
  address payable immutable ADMIN_ADDRESS = payable(address(1));
  address immutable DAO_ADDRESS = address(999);
  address payable immutable DISTRIBUTION_ADDRESS = payable(address(2));
  address immutable ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  Globals globals;
  TokenDistributor distributor;
  DummyTokenDistributorParty dummyParty1 = new DummyTokenDistributorParty();
  DummyTokenDistributorParty dummyParty2 = new DummyTokenDistributorParty();
  DummyERC20 dummyToken1 = new DummyERC20();

  function setUp() public {
    globals = new Globals(DAO_ADDRESS);
    vm.prank(DAO_ADDRESS);
    globals.setAddress(LibGlobals.GLOBAL_DAO_WALLET, DAO_ADDRESS);
    distributor = new TokenDistributor(globals);
  }

  function testEthDistributionSimple() public {
    ITokenDistributor.DistributionInfo memory ds =
        _createEthDistribution(dummyParty1, 0.025e4, 1.337 ether);

    assertEq(DISTRIBUTION_ADDRESS.balance, 0);
    assert(!distributor.wasFeeClaimed(dummyParty1, ds.distributionId));
    vm.prank(ADMIN_ADDRESS);
    distributor.claimFee(ds, DISTRIBUTION_ADDRESS);
    assertEq(DISTRIBUTION_ADDRESS.balance, 0.033425 ether);
    assert(distributor.wasFeeClaimed(dummyParty1, ds.distributionId));

    _createDummyNft(dummyParty1, address(3), 3, 0.34 ether);
    _createDummyNft(dummyParty1, address(4), 4, 0.66 ether);

    assert(!distributor.hasPartyTokenIdClaimed(dummyParty1, 3, ds.distributionId));
    uint256 ethGained1 = _claim(ds, address(3), 3);
    assert(distributor.hasPartyTokenIdClaimed(dummyParty1, 3, ds.distributionId));
    _assertEthApprox(ethGained1, 0.4432155 ether);

    uint256 ethGained2 = _claim(ds, address(4), 4);
    _assertEthApprox(ethGained2, 0.8603595 ether);

    assertEq(address(distributor).balance, 0);
  }

  function testMultiplePartyDistributions() public {
    // distribution 1 (ds1, ETH)
    payable(address(distributor)).transfer(0.1 ether);
    vm.prank(address(dummyParty1)); // must create from party
    ITokenDistributor.DistributionInfo memory ds1 =
        distributor.createNativeDistribution(dummyParty1, ADMIN_ADDRESS, 0.05e4);
    _createDummyNft(dummyParty1, address(1), 1337, 0.7 ether);
    _createDummyNft(dummyParty1, address(2), 1338, 0.3 ether);
    // distribution 2 (ds2, ETH)
    payable(address(distributor)).transfer(0.25 ether);
    vm.prank(address(dummyParty2)); // must create from party
    ITokenDistributor.DistributionInfo memory ds2 =
        distributor.createNativeDistribution(dummyParty2, ADMIN_ADDRESS, 0.05e4);
    _createDummyNft(dummyParty2, address(1), 1337, 0.33 ether);
    _createDummyNft(dummyParty2, address(3), 1338, 0.66 ether);
    // distribution 3 (ds1, dummyToken1)
    dummyToken1.deal(address(distributor), 300 ether);
    vm.prank(address(dummyParty1)); // must create from party
    ITokenDistributor.DistributionInfo memory ds3 =
        distributor.createErc20Distribution(
            IERC20(address(dummyToken1)),
            dummyParty1,
            ADMIN_ADDRESS,
            0.05e4
        );



    // ****** DISTRIBUTION 1 *****
    // receive for id 1
    _assertEthApprox(
      _claim(ds1, address(1), 1337),
      0.0665 ether
    );
    assertEq(
      _daoClaimEthAndReturnDiff(ds1),
      0.005 ether
    );

    // user cant claim again
    vm.expectRevert(abi.encodeWithSelector(
        TokenDistributor.DistributionAlreadyClaimedByPartyTokenError.selector,
        1,
        1337
    ));
    vm.prank(address(1));
    distributor.claim(ds1, 1337);

    // partydao cant claim again
    vm.expectRevert(abi.encodeWithSelector(
        TokenDistributor.DistributionFeeAlreadyClaimedError.selector,
        1
    ));
    vm.prank(ADMIN_ADDRESS);
    distributor.claimFee(ds1, DISTRIBUTION_ADDRESS);

    // ****** DISTRIBUTION 2 *****
    // cant claim if not right user
    vm.prank(address(3));
    vm.expectRevert(abi.encodeWithSelector(
        TokenDistributor.MustOwnTokenError.selector,
        address(3),
        address(1),
        1337
    ));
    distributor.claim(ds2, 1337);
    // claim one
    _assertEthApprox(
      _claim(ds2, address(1), 1337),
      0.078375 ether
    );
    // claim another
    _assertEthApprox(
      _claim(ds2, address(3), 1338),
      0.15675 ether
    );

    // **** DISTRIBUTION 3 (ERC20) *****
    assertEq(dummyToken1.balanceOf((address(1))), 0);
    assertEq(dummyToken1.balanceOf((address(2))), 0);
    assertEq(dummyToken1.balanceOf((address(distributor))), 300 ether);
    vm.prank(address(1));
    distributor.claim(ds3, 1337);
    assertEq(dummyToken1.balanceOf((address(1))), 199.5 ether);
    assertEq(dummyToken1.balanceOf((address(2))), 0 ether);
    assertEq(dummyToken1.balanceOf((address(distributor))), 100.5 ether);
    vm.prank(address(2));
    distributor.claim(ds3, 1338);
    assertEq(dummyToken1.balanceOf((address(1))), 199.5 ether);
    assertEq(dummyToken1.balanceOf((address(2))), 85.5 ether);
    assertEq(dummyToken1.balanceOf((address(distributor))), 15 ether);
    assertEq(dummyToken1.balanceOf(address(9)), 0 ether);
    vm.prank(ADMIN_ADDRESS);
    distributor.claimFee(ds3, payable(address(9)));
    assertEq(dummyToken1.balanceOf(address(9)), 15 ether);

  }

  function testEmergencyDistributionFunctions() public {
    // ETH
    payable(address(distributor)).transfer(50 ether);
    vm.prank(address(dummyParty1)); // must create from party
    distributor.createNativeDistribution(dummyParty1, ADMIN_ADDRESS, 0.05e4);

    // ERC 20
    dummyToken1.deal(address(distributor), 19 ether);
    vm.prank(address(dummyParty1));
    distributor.createErc20Distribution(
        IERC20(address(dummyToken1)),
        dummyParty1,
        ADMIN_ADDRESS,
        0.05e4
    );

    // cant withdraw as non-admin
    vm.expectRevert(abi.encodeWithSelector(
          TokenDistributor.OnlyPartyDaoError.selector,
          address(3),
          DAO_ADDRESS
    ));
    vm.prank(address(3));
    distributor.emergencyWithdraw(
      ITokenDistributor.TokenType.Native,
      ETH_ADDRESS,
      0,
      payable(address(1)),
      10 ether
    );


    // emergency withdraw
    vm.startPrank(DAO_ADDRESS);
    // withdraw ETH
    assertEq(address(5).balance, 0);
    distributor.emergencyWithdraw(
        ITokenDistributor.TokenType.Native,
        ETH_ADDRESS,
        0,
        payable(address(5)),
        10 ether
    );
    assertEq(address(5).balance, 10 ether);
    // withdraw ERC20
    assertEq(dummyToken1.balanceOf(address(4)), 0);
    distributor.emergencyWithdraw(
        ITokenDistributor.TokenType.Erc20,
        address(dummyToken1),
        0,
        payable(address(4)),
        19 ether
    );
    assertEq(dummyToken1.balanceOf(address(4)), 19 ether);
    vm.stopPrank();

    // emergency remove distribution
    assertEq(distributor.getRemainingMemberSupply(dummyParty1, 1), 47.5 ether);
    // non admin can't delete
    vm.prank(address(7));
    vm.expectRevert(abi.encodeWithSelector(
          TokenDistributor.OnlyPartyDaoError.selector,
          address(7),
          DAO_ADDRESS
    ));
    distributor.emergencyRemoveDistribution(
      dummyParty1, 1
    );
    // admin can remove distribution
    vm.prank(DAO_ADDRESS);
    distributor.emergencyRemoveDistribution(
      dummyParty1, 1
    );
    assertEq(distributor.getRemainingMemberSupply(dummyParty1, 1), 0 ether);


    // non-admin can't disable
    vm.expectRevert(abi.encodeWithSelector(
          TokenDistributor.OnlyPartyDaoError.selector,
          address(3),
          DAO_ADDRESS
    ));

    // disable emergency acitons
    vm.prank(address(3));
    distributor.disableEmergencyActions();

    // cant withdraw when emergency actions disabled
    vm.startPrank(DAO_ADDRESS);
    distributor.disableEmergencyActions();
    vm.expectRevert(abi.encodeWithSelector(
        TokenDistributor.EmergencyActionsNotAllowedError.selector
    ));
    distributor.emergencyWithdraw(
        ITokenDistributor.TokenType.Native,
        ETH_ADDRESS,
        0,
        payable(address(5)),
        1 ether
    );

    // cant remove when emergency actions disabled
    vm.expectRevert(abi.encodeWithSelector(
        TokenDistributor.EmergencyActionsNotAllowedError.selector
    ));
    distributor.emergencyRemoveDistribution(
      dummyParty1, 1
    );
  }

  function testZeroSupplyDistributionCreation() public {
    // ensure amount needs to be > 0
    vm.prank(address(dummyParty1)); // must create from party
    vm.expectRevert(abi.encodeWithSelector(
      TokenDistributor.InvalidDistributionSupplyError.selector,
      0
    ));
    distributor.createNativeDistribution(dummyParty1, ADMIN_ADDRESS, 0);

    // ensure needs to be able to take fee
    vm.deal(address(distributor), 10);
    vm.expectRevert(abi.encodeWithSelector(
      TokenDistributor.InvalidFeeBpsError.selector,
      1.1e4
    ));
    vm.prank(address(dummyParty1));
    distributor.createNativeDistribution(dummyParty1, ADMIN_ADDRESS, 1.1e4); // 110%
  }

  function testDistributeZero() public {
    vm.deal(address(distributor), 100 ether);

    vm.prank(address(dummyParty1)); // must send from party
    ITokenDistributor.DistributionInfo memory ds =
        distributor.createNativeDistribution(dummyParty1, ADMIN_ADDRESS, 0);

    _createDummyNft(dummyParty1, address(5), 420, 0);

    uint256 balanceBefore = address(5).balance;
    vm.prank(address(5));
    distributor.claim(ds, 420);
    assertEq(address(5).balance, balanceBefore);
  }

  function testMaliciousDistributor() public {
     // test that malicioius party cant claim more than total member supply
    vm.deal(address(distributor), 0.5 ether);

    vm.prank(address(dummyParty1));
    ITokenDistributor.DistributionInfo memory ds =
        distributor.createNativeDistribution(dummyParty1, ADMIN_ADDRESS, 0.05e4);
    _createDummyNft(dummyParty1, address(5), 420, 2 ether); // malicious amount 2x

    vm.deal(address(distributor), 100 ether);

    uint256 ethDiff = _claim(
      ds, address(5), 420
    );
    _assertEthApprox(ethDiff, 0.475 ether); // should max out
  }

  // to handle weird rounding error
  function _assertEthApprox(uint256 givenAmount, uint256 expectedAmount) private {
    assertApproxEqAbs(givenAmount, expectedAmount, 0.0000000000001 ether);
  }

  function _daoClaimEthAndReturnDiff(
    ITokenDistributor.DistributionInfo memory di
  ) private returns (uint256) {
      vm.prank(ADMIN_ADDRESS);
      uint256 beforeBal = DISTRIBUTION_ADDRESS.balance;
      distributor.claimFee(di, DISTRIBUTION_ADDRESS);
      uint256 afterBal = DISTRIBUTION_ADDRESS.balance;
      return afterBal - beforeBal;
  }

  function _createDummyNft(
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
    uint16 feeSplitBps,
    uint256 ethAmount
) private returns (ITokenDistributor.DistributionInfo memory) {

    payable(address(distributor)).transfer(ethAmount);
    vm.prank(address(dummyParty)); // must create from party
    return distributor.createNativeDistribution(dummyParty, ADMIN_ADDRESS, feeSplitBps);
  }

  function _claim(
    ITokenDistributor.DistributionInfo memory ds,
    address prankAs,
    uint256 tokenId
  ) private returns (uint256) {
    uint256 initialEth = prankAs.balance;
    vm.prank(prankAs);
    uint256 startGas = gasleft();
    distributor.claim(ds, tokenId);
    uint256 endGas = gasleft();
    uint256 gasUsed = startGas - endGas;
    uint256 newBalance = prankAs.balance;
    uint256 ethGained = newBalance - (initialEth + gasUsed);
    return ethGained;
  }
}
