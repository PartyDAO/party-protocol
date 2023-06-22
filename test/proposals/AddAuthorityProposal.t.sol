// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/AddAuthorityProposal.sol";

import "../TestUtils.sol";

contract TestableAddAuthorityProposal is AddAuthorityProposal {
    mapping(address => bool) public isAuthority;

    error OnlySelfError();

    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert OnlySelfError();
        }
        _;
    }

    function execute(
        IProposalExecutionEngine.ExecuteProposalParams calldata params
    ) external payable returns (bytes memory nextProgressData) {
        nextProgressData = _executeAddAuthority(params);
    }

    // The proposal will call this function on itself to add the newly created
    // crowdfund as an authority.
    function addAuthority(address authority) external onlySelf {
        isAuthority[authority] = true;
    }
}

contract MockCrowdfundFactory {
    ReraiseETHCrowdfund public expectedCrowdfund;

    constructor(ReraiseETHCrowdfund expectedCrowdfund_) {
        expectedCrowdfund = expectedCrowdfund_;
    }

    function createReraiseETHCrowdfund(
        ETHCrowdfundBase.ETHCrowdfundOptions memory,
        bytes memory
    ) public payable returns (ReraiseETHCrowdfund inst) {
        return expectedCrowdfund;
    }
}

contract AddAuthorityProposalTest is Test, TestUtils {
    TestableAddAuthorityProposal proposal;
    MockCrowdfundFactory crowdfundFactory;
    ReraiseETHCrowdfund expectedCrowdfund;

    constructor() {
        proposal = new TestableAddAuthorityProposal();
        expectedCrowdfund = new ReraiseETHCrowdfund(IGlobals(address(0)));
        crowdfundFactory = new MockCrowdfundFactory(expectedCrowdfund);
    }

    function test_executeAddAuthority_withNoCalldata() public {
        assertEq(proposal.isAuthority(address(this)), false);

        AddAuthorityProposal.AddAuthorityProposalData memory data = AddAuthorityProposal
            .AddAuthorityProposalData({ target: address(this), callData: "" });

        // Execute the proposal.
        bytes memory nextProgressData = proposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: "",
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            })
        );

        assertEq(nextProgressData.length, 0);
        assertEq(proposal.isAuthority(address(this)), true);
    }

    function test_executeAddAuthority_withResultFromCalldata() public {
        assertEq(proposal.isAuthority(address(expectedCrowdfund)), false);

        ETHCrowdfundBase.ETHCrowdfundOptions memory callData;
        AddAuthorityProposal.AddAuthorityProposalData memory data = AddAuthorityProposal
            .AddAuthorityProposalData({
                target: address(crowdfundFactory),
                callData: abi.encodeCall(crowdfundFactory.createReraiseETHCrowdfund, (callData, ""))
            });

        // Execute the proposal.
        bytes memory nextProgressData = proposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: "",
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            })
        );

        assertEq(nextProgressData.length, 0);
        assertEq(proposal.isAuthority(address(expectedCrowdfund)), true);
    }
}
