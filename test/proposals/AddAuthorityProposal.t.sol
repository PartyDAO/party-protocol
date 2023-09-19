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

contract MockContract {
    function mockFunction() public pure returns (uint256) {
        return 42;
    }
}

contract MockFactory {
    MockContract public expectedContract;

    constructor(MockContract expectedContract_) {
        expectedContract = expectedContract_;
    }

    function createMockContract(bytes memory) public payable returns (MockContract inst) {
        return expectedContract;
    }
}

contract AddAuthorityProposalTest is Test, TestUtils {
    TestableAddAuthorityProposal proposal;
    MockFactory factory;
    MockContract expectedContract;

    constructor() {
        proposal = new TestableAddAuthorityProposal();
        expectedContract = new MockContract();
        factory = new MockFactory(expectedContract);
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
        assertEq(proposal.isAuthority(address(expectedContract)), false);

        bytes memory callData = abi.encode(_randomBytes32());
        AddAuthorityProposal.AddAuthorityProposalData memory data = AddAuthorityProposal
            .AddAuthorityProposalData({
                target: address(factory),
                callData: abi.encodeCall(factory.createMockContract, (callData))
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
        assertEq(proposal.isAuthority(address(expectedContract)), true);
    }
}
