// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import { IERC20 } from "./../../contracts/tokens/IERC20.sol";
import { MockERC20 } from "forge-std/mocks/MockERC20.sol";
import { SetupPartyHelper } from "../utils/SetupPartyHelper.sol";
import { PushDistributor } from "./../../contracts/distribution/PushDistributor.sol";
import { ArbitraryCallsProposal } from "./../../contracts/proposals/ArbitraryCallsProposal.sol";
import { PartyGovernance } from "./../../contracts/party/PartyGovernance.sol";
import { ProposalExecutionEngine } from "./../../contracts/proposals/ProposalExecutionEngine.sol";

contract PushDistributorTest is SetupPartyHelper {
    PushDistributor pushDistributor;
    IERC20 erc20;
    address[] members;

    IERC20 private constant ETH_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    constructor() SetupPartyHelper(false) {}

    function setUp() public override {
        super.setUp();

        // Deploy PushDistributor
        pushDistributor = new PushDistributor();

        // Deploy mock ERC20
        erc20 = IERC20(address(new MockERC20()));

        // Setup Party with 100 ETH and 1000 mock ERC20
        deal(address(party), 100e18);
        deal(address(erc20), address(party), 1000e18);

        // Setup members
        members = new address[](4);
        members[0] = john;
        members[1] = danny;
        members[2] = steve;
        members[3] = address(this);

        // Sort the addresses from lowest to highest.
        for (uint256 i = 0; i < members.length; i++) {
            for (uint256 j = i + 1; j < members.length; j++) {
                if (members[i] > members[j]) {
                    (members[i], members[j]) = (members[j], members[i]);
                }
            }
        }

        // Reset this contract's ETH balance for testing
        deal(address(this), 0);
    }

    function test_distribute_withERC20() public {
        uint256 amountToDistribute = 100e18;

        // Create a proposal to distribute the tokens
        PartyGovernance.Proposal memory proposal = _createProposal(erc20, amountToDistribute);

        // Propose and execute the proposal
        _proposePassAndExecuteProposal(proposal);

        // Check if the distribution was successful
        // John, Danny, Steve who each have 100 / 301 voting power should
        // receive 100 / 301 * 100e18 tokens
        assertEq(erc20.balanceOf(john), (100 * amountToDistribute) / 301);
        assertEq(erc20.balanceOf(danny), (100 * amountToDistribute) / 301);
        assertEq(erc20.balanceOf(steve), (100 * amountToDistribute) / 301);
        // The contract which has 1 / 301 voting power should receive
        // 1 / 301 * 100e18 tokens
        assertEq(erc20.balanceOf(address(this)), (1 * amountToDistribute) / 301);
    }

    function test_distribute_withETH() public {
        uint256 amountToDistribute = 10e18;

        // Create a proposal to distribute the tokens
        PartyGovernance.Proposal memory proposal = _createProposal(ETH_ADDRESS, amountToDistribute);

        // Propose and execute the proposal
        _proposePassAndExecuteProposal(proposal);

        // Check if the distribution was successful
        // John, Danny, Steve who each have 100 / 301 voting power should
        // receive 100 / 301 * 10e18 ETH
        assertEq(john.balance, (100 * amountToDistribute) / 301);
        assertEq(danny.balance, (100 * amountToDistribute) / 301);
        assertEq(steve.balance, (100 * amountToDistribute) / 301);
        // The contract which has 1 / 301 voting power should receive
        // 1 / 301 * 10e18 ETH
        assertEq(address(this).balance, (1 * amountToDistribute) / 301);
    }

    function _createProposal(
        IERC20 token,
        uint256 amount
    ) internal view returns (PartyGovernance.Proposal memory proposal) {
        if (token != ETH_ADDRESS) {
            ArbitraryCallsProposal.ArbitraryCall[]
                memory arbCalls = new ArbitraryCallsProposal.ArbitraryCall[](2);

            arbCalls[0] = ArbitraryCallsProposal.ArbitraryCall({
                target: payable(address(token)),
                value: 0,
                data: abi.encodeCall(IERC20.approve, (address(pushDistributor), amount)),
                expectedResultHash: ""
            });
            arbCalls[1] = ArbitraryCallsProposal.ArbitraryCall({
                target: payable(address(pushDistributor)),
                value: 0,
                data: abi.encodeCall(
                    PushDistributor.distribute,
                    (token, members, amount, party.lastProposalId() + 1)
                ),
                expectedResultHash: ""
            });

            return
                PartyGovernance.Proposal({
                    maxExecutableTime: type(uint40).max,
                    cancelDelay: 0,
                    proposalData: abi.encodeWithSelector(
                        bytes4(uint32(ProposalExecutionEngine.ProposalType.ArbitraryCalls)),
                        arbCalls
                    )
                });
        } else {
            ArbitraryCallsProposal.ArbitraryCall[]
                memory arbCalls = new ArbitraryCallsProposal.ArbitraryCall[](1);

            arbCalls[0] = ArbitraryCallsProposal.ArbitraryCall({
                target: payable(address(pushDistributor)),
                value: amount,
                data: abi.encodeCall(
                    PushDistributor.distribute,
                    (token, members, amount, party.lastProposalId() + 1)
                ),
                expectedResultHash: ""
            });

            return
                PartyGovernance.Proposal({
                    maxExecutableTime: type(uint40).max,
                    cancelDelay: 0,
                    proposalData: abi.encodeWithSelector(
                        bytes4(uint32(ProposalExecutionEngine.ProposalType.ArbitraryCalls)),
                        arbCalls
                    )
                });
        }
    }

    receive() external payable {}
}
