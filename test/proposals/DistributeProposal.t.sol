// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/DistributeProposal.sol";

import "../TestUtils.sol";

contract TestableDistributeProposal is DistributeProposal {
    event MockCreateDistribution(
        address caller,
        ITokenDistributor.TokenType tokenType,
        address token,
        uint256 tokenId
    );

    function execute(
        IProposalExecutionEngine.ExecuteProposalParams calldata params
    ) external payable returns (bytes memory nextProgressData) {
        nextProgressData = _executeDistribute(params);
    }

    // This is here because during the proposal, the party will call
    // `distribute()` on itself.
    function distribute(
        uint256,
        ITokenDistributor.TokenType tokenType,
        address token,
        uint256 tokenId
    ) external returns (ITokenDistributor.DistributionInfo memory distInfo) {
        if (msg.sender != address(this)) {
            revert("FAIL");
        }

        emit MockCreateDistribution(msg.sender, tokenType, token, tokenId);

        return distInfo;
    }
}

contract DistributeProposalTest is Test, TestUtils {
    event MockCreateDistribution(
        address caller,
        ITokenDistributor.TokenType tokenType,
        address token,
        uint256 tokenId
    );

    TestableDistributeProposal distributeProposal;

    address constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor() {
        distributeProposal = new TestableDistributeProposal();
    }

    function test_canDistribute() public {
        _expectEmit0();
        emit MockCreateDistribution(
            address(distributeProposal),
            ITokenDistributor.TokenType.Native,
            NATIVE_TOKEN_ADDRESS,
            0
        );
        // Execute the proposal.
        vm.deal(address(distributeProposal), 1 ether);
        bytes memory nextProgressData = distributeProposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: "",
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(
                    DistributeProposal.DistributeProposalData({
                        amount: 1 ether,
                        tokenType: ITokenDistributor.TokenType.Native,
                        token: NATIVE_TOKEN_ADDRESS,
                        tokenId: 0
                    })
                )
            })
        );
        assertEq(nextProgressData.length, 0);
    }
}
