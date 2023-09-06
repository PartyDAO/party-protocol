// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../../contracts/crowdfund/ContributionRouter.sol";
import "../TestUtils.sol";

contract ContributionRouterTest is TestUtils {
    event FeePerContributionUpdated(uint96 oldFeePerContribution, uint96 newFeePerContribution);
    event ReceivedFees(address indexed sender, uint256 amount);
    event ClaimedFees(address indexed partyDao, address indexed recipient, uint256 amount);

    address owner;
    uint96 feePerContribution;
    ContributionRouter router;

    constructor() {
        owner = _randomAddress();
        feePerContribution = 0.01 ether;
        router = new ContributionRouter(owner, feePerContribution);
    }

    function test_initialization() public {
        assertEq(router.OWNER(), owner);
        assertEq(router.feePerContribution(), feePerContribution);
    }

    function test_callWithFee_works() external {
        MockPayableContract target = new MockPayableContract();
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);
        uint256 feeAmount = feePerContribution;
        vm.expectEmit(true, true, true, true);
        emit ReceivedFees(msg.sender, feeAmount);
        router.callWithFee{ value: amount }(
            address(target),
            abi.encodeWithSelector(MockPayableContract.pay.selector)
        );
        assertEq(address(target).balance, amount - feeAmount);
        assertEq(address(router).balance, feeAmount);
    }

    function test_callWithFee_insufficientFee() public {
        MockPayableContract target = new MockPayableContract();
        uint256 amount = feePerContribution - 1;
        vm.deal(address(this), amount);
        vm.expectRevert(stdError.arithmeticError);
        router.callWithFee{ value: amount }(
            address(target),
            abi.encodeWithSelector(MockPayableContract.pay.selector)
        );
    }

    function test_setFeePerContribution_works() external {
        uint96 newFeePerContribution = 0.02 ether;
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit FeePerContributionUpdated(feePerContribution, newFeePerContribution);
        router.setFeePerContribution(newFeePerContribution);
        assertEq(router.feePerContribution(), newFeePerContribution);
    }

    function test_setFeePerContribution_onlyOwner() external {
        uint96 newFeePerContribution = 0.02 ether;
        vm.expectRevert(ContributionRouter.OnlyOwner.selector);
        router.setFeePerContribution(newFeePerContribution);
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
