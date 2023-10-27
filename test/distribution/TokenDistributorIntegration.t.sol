// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { TokenDistributor, ITokenDistributor } from "../../contracts/distribution/TokenDistributor.sol";
import { PartyGovernance } from "../../contracts/party/PartyGovernance.sol";
import { ProposalExecutionEngine } from "../../contracts/proposals/ProposalExecutionEngine.sol";
import { DistributeProposal } from "../../contracts/proposals/DistributeProposal.sol";
import { LibGlobals } from "../../contracts/globals/LibGlobals.sol";

contract TokenDistributorIntegrationTest is SetupPartyHelper {
    constructor() SetupPartyHelper(false) {}

    function test_tokenDistributor_claimAllDistributions() public {
        vm.deal(address(party), 1 ether);

        PartyGovernance.Proposal memory distributionProposal = PartyGovernance.Proposal({
            maxExecutableTime: type(uint40).max,
            cancelDelay: 0,
            proposalData: abi.encodeWithSelector(
                bytes4(uint32(ProposalExecutionEngine.ProposalType.Distribute)),
                DistributeProposal.DistributeProposalData({
                    amount: 1 ether,
                    tokenType: ITokenDistributor.TokenType.Native,
                    tokenId: 0,
                    token: address(0)
                })
            )
        });
        _proposePassAndExecuteProposal(distributionProposal);

        // Claim the distribution
        TokenDistributor distributor = TokenDistributor(
            globals.getAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR)
        );
        ITokenDistributor.DistributionInfo memory info = ITokenDistributor.DistributionInfo({
            tokenType: ITokenDistributor.TokenType.Native,
            distributionId: 1,
            party: party,
            feeRecipient: payable(0),
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            memberSupply: 1 ether,
            fee: 0,
            totalShares: 301
        });

        uint256 johnBalanceBefore = john.balance;
        uint256 dannyBalanceBefore = danny.balance;
        uint256 steveBalanceBefore = steve.balance;
        uint256 thisBalanceBefore = address(this).balance;

        vm.prank(john);
        distributor.claim(info, 1);

        vm.prank(danny);
        distributor.claim(info, 2);

        vm.prank(steve);
        distributor.claim(info, 3);

        // Claim for this
        distributor.claim(info, 4);

        //assertEq(address(distributor).balance, 0);
        assertEq(john.balance, johnBalanceBefore + ((uint256(1 ether) * 100) / 301));
        assertEq(danny.balance, dannyBalanceBefore + ((uint256(1 ether) * 100) / 301));
        assertEq(steve.balance, steveBalanceBefore + ((uint256(1 ether) * 100) / 301));
        assertEq(address(this).balance, thisBalanceBefore + ((uint256(1 ether) * 1) / 301));
    }

    function test_tokenDistributor_claimTokenMintedAfterDistribution() public {
        vm.deal(address(party), 1 ether);

        PartyGovernance.Proposal memory distributionProposal = PartyGovernance.Proposal({
            maxExecutableTime: type(uint40).max,
            cancelDelay: 0,
            proposalData: abi.encodeWithSelector(
                bytes4(uint32(ProposalExecutionEngine.ProposalType.Distribute)),
                DistributeProposal.DistributeProposalData({
                    amount: 1 ether,
                    tokenType: ITokenDistributor.TokenType.Native,
                    tokenId: 0,
                    token: address(0)
                })
            )
        });
        _proposePassAndExecuteProposal(distributionProposal);

        vm.roll(block.number + 10);

        party.increaseTotalVotingPower(100);
        uint256 newTokenId = party.mint(john, 100, john);
        assertEq(party.votingPowerByTokenId(newTokenId), 100);

        // Claim the distribution
        TokenDistributor distributor = TokenDistributor(
            globals.getAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR)
        );
        ITokenDistributor.DistributionInfo memory info = ITokenDistributor.DistributionInfo({
            tokenType: ITokenDistributor.TokenType.Native,
            distributionId: 1,
            party: party,
            feeRecipient: payable(0),
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            memberSupply: 1 ether,
            fee: 0,
            totalShares: 301
        });

        vm.prank(john);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenDistributor.TokenIdAboveMaxError.selector,
                newTokenId,
                newTokenId - 1
            )
        );
        distributor.claim(info, newTokenId);

        // claims are still the expected amount
        uint256 johnBalanceBefore = john.balance;
        uint256 dannyBalanceBefore = danny.balance;
        uint256 steveBalanceBefore = steve.balance;
        uint256 thisBalanceBefore = address(this).balance;
        vm.prank(john);
        distributor.claim(info, 1);
        vm.prank(danny);
        distributor.claim(info, 2);
        vm.prank(steve);
        distributor.claim(info, 3);
        distributor.claim(info, 4);
        assertEq(john.balance, johnBalanceBefore + ((uint256(1 ether) * 100) / 301));
        assertEq(danny.balance, dannyBalanceBefore + ((uint256(1 ether) * 100) / 301));
        assertEq(steve.balance, steveBalanceBefore + ((uint256(1 ether) * 100) / 301));
        assertEq(address(this).balance, thisBalanceBefore + ((uint256(1 ether) * 1) / 301));
    }

    /// @notice This test emulates an NFT crowdfund by setting the total voting power before minting cards.
    function test_tokenDistributor_claimTokenMintedAfterDistribution_unclaimedPartyCard() public {
        vm.deal(address(party), 1 ether);
        party.increaseTotalVotingPower(100);

        PartyGovernance.Proposal memory distributionProposal = PartyGovernance.Proposal({
            maxExecutableTime: type(uint40).max,
            cancelDelay: 0,
            proposalData: abi.encodeWithSelector(
                bytes4(uint32(ProposalExecutionEngine.ProposalType.Distribute)),
                DistributeProposal.DistributeProposalData({
                    amount: 1 ether,
                    tokenType: ITokenDistributor.TokenType.Native,
                    tokenId: 0,
                    token: address(0)
                })
            )
        });
        _proposePassAndExecuteProposal(distributionProposal);

        vm.roll(block.number + 10);

        uint256 newTokenId = party.mint(john, 100, john);
        assertEq(party.votingPowerByTokenId(newTokenId), 100);

        // Claim the distribution
        TokenDistributor distributor = TokenDistributor(
            globals.getAddress(LibGlobals.GLOBAL_TOKEN_DISTRIBUTOR)
        );
        ITokenDistributor.DistributionInfo memory info = ITokenDistributor.DistributionInfo({
            tokenType: ITokenDistributor.TokenType.Native,
            distributionId: 1,
            party: party,
            feeRecipient: payable(0),
            token: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            memberSupply: 1 ether,
            fee: 0,
            totalShares: 401
        });

        // claims are still the expected amount
        uint256 johnBalanceBefore = john.balance;
        uint256 dannyBalanceBefore = danny.balance;
        uint256 steveBalanceBefore = steve.balance;
        uint256 thisBalanceBefore = address(this).balance;
        vm.prank(john);
        distributor.claim(info, 1);
        vm.prank(john);
        distributor.claim(info, newTokenId);
        vm.prank(danny);
        distributor.claim(info, 2);
        vm.prank(steve);
        distributor.claim(info, 3);
        distributor.claim(info, 4);
        assertEq(
            john.balance,
            johnBalanceBefore + ((uint256(1 ether) * 200) / 401 - 1 /* rounding error */)
        );
        assertEq(danny.balance, dannyBalanceBefore + ((uint256(1 ether) * 100) / 401));
        assertEq(steve.balance, steveBalanceBefore + ((uint256(1 ether) * 100) / 401));
        assertEq(address(this).balance, thisBalanceBefore + ((uint256(1 ether) * 1) / 401));
    }

    // Enable to receive eth
    receive() external payable {}
}
