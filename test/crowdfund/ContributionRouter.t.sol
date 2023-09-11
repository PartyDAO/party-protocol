// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../../contracts/crowdfund/ContributionRouter.sol";
import "../TestUtils.sol";

contract ContributionRouterTest is TestUtils {
    event FeePerMintUpdated(uint96 oldFeePerMint, uint96 newFeePerMint);
    event ReceivedFees(address indexed sender, uint256 amount);
    event ClaimedFees(address indexed partyDao, address indexed recipient, uint256 amount);

    address owner;
    uint96 feePerMint;
    ContributionRouter router;

    function setUp() public {
        owner = _randomAddress();
        feePerMint = 0.01 ether;
        router = new ContributionRouter(owner, feePerMint);
    }

    function test_initialization() public {
        assertEq(router.OWNER(), owner);
        assertEq(router.feePerMint(), feePerMint);
    }

    function test_fallback_works() external {
        MockPayableContract target = new MockPayableContract();
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);
        uint256 feeAmount = feePerMint;
        vm.expectEmit(true, true, true, true);
        emit ReceivedFees(address(this), feeAmount);
        (bool success, bytes memory res) = address(router).call{ value: amount }(
            abi.encodePacked(abi.encodeWithSelector(MockPayableContract.pay.selector), target)
        );
        assertEq(success, true);
        assertEq(res.length, 0);
        assertEq(address(target).balance, amount - feeAmount);
        assertEq(address(router).balance, feeAmount);
    }

    function test_fallback_insufficientFee() public {
        MockPayableContract target = new MockPayableContract();
        uint256 amount = feePerMint - 1;
        vm.deal(address(this), amount);
        (bool success, bytes memory res) = address(router).call{ value: amount }(
            abi.encodePacked(abi.encodeWithSelector(MockPayableContract.pay.selector), target)
        );
        assertEq(success, false);
        assertEq(res, stdError.arithmeticError);
    }

    function test_setFeePerMint_works() external {
        uint96 newFeePerMint = 0.02 ether;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit FeePerMintUpdated(feePerMint, newFeePerMint);
        router.setFeePerMint(newFeePerMint);
        assertEq(router.feePerMint(), newFeePerMint);
    }

    function test_setFeePerMint_onlyOwner() external {
        uint96 newFeePerMint = 0.02 ether;
        vm.expectRevert(ContributionRouter.OnlyOwner.selector);
        router.setFeePerMint(newFeePerMint);
    }

    function test_claimFees_works() external {
        address payable recipient = payable(_randomAddress());
        uint256 balance = _randomUint256();
        vm.deal(address(router), balance);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ClaimedFees(owner, recipient, balance);
        router.claimFees(recipient);
    }

    function test_claimFees_onlyOwner() external {
        address payable recipient = payable(_randomAddress());
        vm.expectRevert(ContributionRouter.OnlyOwner.selector);
        router.claimFees(recipient);
    }
}

contract MockPayableContract {
    event Paid(uint256 amount);

    function pay() external payable {
        emit Paid(msg.value);
    }

    receive() external payable {}
}
