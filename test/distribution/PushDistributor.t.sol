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
import { ERC721Receiver } from "./../../contracts/tokens/ERC721Receiver.sol";

contract PushDistributorTest is SetupPartyHelper {
    event Distributed(IERC20 token, address[] members, uint256 amount);

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

    function test_distribute_withChangingVotingPowerAndTotalVotingPower() public {
        uint256 amountToDistribute = 100e18;

        // Create a proposal to distribute the tokens
        PartyGovernance.Proposal memory proposal = _createProposal(erc20, amountToDistribute);

        // Propose the proposal
        _proposeAndPassProposal(proposal);

        // Mint new members (should not affect the distribution)
        address brian = _randomAddress();
        address aryeh = _randomAddress();
        party.increaseTotalVotingPower(200);
        party.mint(brian, 100, brian);
        party.mint(aryeh, 100, aryeh);

        // Execute the proposal
        _executeProposal(party.lastProposalId(), proposal);

        // Check if the distribution was successful
        // John, Danny, Steve who each have 100 / 301 voting power at time of
        // proposal should receive 100 / 301 * 100e18 tokens
        assertEq(erc20.balanceOf(john), (100 * amountToDistribute) / 301);
        assertEq(erc20.balanceOf(danny), (100 * amountToDistribute) / 301);
        assertEq(erc20.balanceOf(steve), (100 * amountToDistribute) / 301);
        // The contract which has 1 / 301 voting power at time of proposal
        // should receive 1 / 301 * 100e18 tokens
        assertEq(erc20.balanceOf(address(this)), (1 * amountToDistribute) / 301);
        // Brian and Aryeh should not receive any tokens
        assertEq(erc20.balanceOf(brian), 0);
        assertEq(erc20.balanceOf(aryeh), 0);
    }

    function test_distribute_doesNotRevertIfMemberCannotReceive() public {
        address newMember = address(new CannotReceiveETH());

        _addMember(newMember);

        uint256 amountToDistribute = 100e18;

        // Create a proposal to distribute the tokens
        PartyGovernance.Proposal memory proposal = _createProposal(ETH_ADDRESS, amountToDistribute);

        // Propose and execute the proposal
        _proposePassAndExecuteProposal(proposal);

        // Check if the distribution was successful
        // John, Danny, Steve who each have 100 / 401 voting power should
        // receive 100 / 401 * 100e18 tokens
        assertEq(john.balance, (100 * amountToDistribute) / 401);
        assertEq(danny.balance, (100 * amountToDistribute) / 401);
        assertEq(steve.balance, (100 * amountToDistribute) / 401);
        // The contract which has 1 / 401 voting power should receive
        // 1 / 401 * 100e18 tokens
        assertEq(address(this).balance, (1 * amountToDistribute) / 401);
        // The new member should not receive any tokens because it cannot receive
        assertEq(newMember.balance, 0);
        // The Party should receive any remaining tokens
        assertEq(address(party).balance, (100 * amountToDistribute) / 401 + 1);
    }

    function test_distribute_revertIfNotEnoughETH() public {
        uint256 amountToDistribute = 10e18;

        ArbitraryCallsProposal.ArbitraryCall[]
            memory arbCalls = new ArbitraryCallsProposal.ArbitraryCall[](1);

        arbCalls[0] = ArbitraryCallsProposal.ArbitraryCall({
            target: payable(address(pushDistributor)),
            value: amountToDistribute - 1, // Not enough ETH
            data: abi.encodeCall(
                PushDistributor.distribute,
                (ETH_ADDRESS, members, amountToDistribute, party.lastProposalId() + 1)
            ),
            expectedResultHash: ""
        });

        {
            PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
                maxExecutableTime: type(uint40).max,
                cancelDelay: 0,
                proposalData: abi.encodeWithSelector(
                    bytes4(uint32(ProposalExecutionEngine.ProposalType.ArbitraryCalls)),
                    arbCalls
                )
            });

            uint256 proposalId = _proposeAndPassProposal(proposal);

            vm.expectRevert(
                abi.encodeWithSelector(
                    ArbitraryCallsProposal.ArbitraryCallFailedError.selector,
                    abi.encodeWithSelector(
                        PushDistributor.NotEnoughETH.selector,
                        amountToDistribute,
                        amountToDistribute - 1
                    )
                )
            );
            _executeProposal(proposalId, proposal);
        }

        // Try with enough ETH this time and pass
        {
            arbCalls[0].value = amountToDistribute;
            arbCalls[0].data = abi.encodeCall(
                PushDistributor.distribute,
                (ETH_ADDRESS, members, amountToDistribute, party.lastProposalId() + 1)
            );
            PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
                maxExecutableTime: type(uint40).max,
                cancelDelay: 0,
                proposalData: abi.encodeWithSelector(
                    bytes4(uint32(ProposalExecutionEngine.ProposalType.ArbitraryCalls)),
                    arbCalls
                )
            });

            _proposePassAndExecuteProposal(proposal);
        }
    }

    function test_distribute_withERC20AndETH() public {
        uint256 amountToDistribute = 100e18;

        ArbitraryCallsProposal.ArbitraryCall[]
            memory arbCalls = new ArbitraryCallsProposal.ArbitraryCall[](2);

        arbCalls[0] = ArbitraryCallsProposal.ArbitraryCall({
            target: payable(address(erc20)),
            value: 0,
            data: abi.encodeCall(IERC20.approve, (address(pushDistributor), amountToDistribute)),
            expectedResultHash: ""
        });
        arbCalls[1] = ArbitraryCallsProposal.ArbitraryCall({
            target: payable(address(pushDistributor)),
            value: 10e18, // 10 ETH
            data: abi.encodeCall(
                PushDistributor.distribute,
                (erc20, members, amountToDistribute, party.lastProposalId() + 1)
            ),
            expectedResultHash: ""
        });

        {
            PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
                maxExecutableTime: type(uint40).max,
                cancelDelay: 0,
                proposalData: abi.encodeWithSelector(
                    bytes4(uint32(ProposalExecutionEngine.ProposalType.ArbitraryCalls)),
                    arbCalls
                )
            });

            uint256 proposalId = _proposeAndPassProposal(proposal);

            _executeProposal(proposalId, proposal);
        }

        // Check that ETH was sent back
        assertEq(address(party).balance, 100e18);
    }

    function test_distribute_revertIfWrongProposalId() public {
        uint256 amountToDistribute = 10e18;

        ArbitraryCallsProposal.ArbitraryCall[]
            memory arbCalls = new ArbitraryCallsProposal.ArbitraryCall[](1);

        arbCalls[0] = ArbitraryCallsProposal.ArbitraryCall({
            target: payable(address(pushDistributor)),
            value: amountToDistribute,
            data: abi.encodeCall(
                PushDistributor.distribute,
                (ETH_ADDRESS, members, amountToDistribute, 2) // Wrong proposal ID
            ),
            expectedResultHash: ""
        });

        {
            PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
                maxExecutableTime: type(uint40).max,
                cancelDelay: 0,
                proposalData: abi.encodeWithSelector(
                    bytes4(uint32(ProposalExecutionEngine.ProposalType.ArbitraryCalls)),
                    arbCalls
                )
            });

            uint256 proposalId = _proposeAndPassProposal(proposal);

            vm.expectRevert(
                abi.encodeWithSelector(
                    ArbitraryCallsProposal.ArbitraryCallFailedError.selector,
                    abi.encodeWithSelector(PushDistributor.WrongProposalId.selector, 2)
                )
            );
            _executeProposal(proposalId, proposal);
        }

        // Try with the correct proposal ID this time and pass
        {
            arbCalls[0].data = abi.encodeCall(
                PushDistributor.distribute,
                (ETH_ADDRESS, members, amountToDistribute, party.lastProposalId() + 1)
            );
            PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
                maxExecutableTime: type(uint40).max,
                cancelDelay: 0,
                proposalData: abi.encodeWithSelector(
                    bytes4(uint32(ProposalExecutionEngine.ProposalType.ArbitraryCalls)),
                    arbCalls
                )
            });

            _proposePassAndExecuteProposal(proposal);
        }
    }

    function test_distribute_revertIfMembersNotSorted() public {
        uint256 amountToDistribute = 10e18;

        address[] memory membersNotSorted = members;
        (membersNotSorted[0], membersNotSorted[1]) = (membersNotSorted[1], membersNotSorted[0]);

        ArbitraryCallsProposal.ArbitraryCall[]
            memory arbCalls = new ArbitraryCallsProposal.ArbitraryCall[](1);

        arbCalls[0] = ArbitraryCallsProposal.ArbitraryCall({
            target: payable(address(pushDistributor)),
            value: amountToDistribute,
            data: abi.encodeCall(
                PushDistributor.distribute,
                // Members not sorted
                (ETH_ADDRESS, membersNotSorted, amountToDistribute, party.lastProposalId() + 1)
            ),
            expectedResultHash: ""
        });

        {
            PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
                maxExecutableTime: type(uint40).max,
                cancelDelay: 0,
                proposalData: abi.encodeWithSelector(
                    bytes4(uint32(ProposalExecutionEngine.ProposalType.ArbitraryCalls)),
                    arbCalls
                )
            });

            uint256 proposalId = _proposeAndPassProposal(proposal);

            vm.expectRevert(
                abi.encodeWithSelector(
                    ArbitraryCallsProposal.ArbitraryCallFailedError.selector,
                    abi.encodePacked(PushDistributor.MembersNotSorted.selector)
                )
            );
            _executeProposal(proposalId, proposal);
        }

        // Try with sorted members this time and pass
        {
            arbCalls[0].data = abi.encodeCall(
                PushDistributor.distribute,
                (ETH_ADDRESS, members, amountToDistribute, party.lastProposalId() + 1)
            );
            PartyGovernance.Proposal memory proposal = PartyGovernance.Proposal({
                maxExecutableTime: type(uint40).max,
                cancelDelay: 0,
                proposalData: abi.encodeWithSelector(
                    bytes4(uint32(ProposalExecutionEngine.ProposalType.ArbitraryCalls)),
                    arbCalls
                )
            });

            _proposePassAndExecuteProposal(proposal);
        }
    }

    function test_distribute_revertIfWrongMembers() public {
        address lastMember = members[members.length - 1];

        // Remove the last member
        members.pop();

        uint256 amountToDistribute = 10e18;

        PartyGovernance.Proposal memory proposal = _createProposal(ETH_ADDRESS, amountToDistribute);

        uint256 proposalId = _proposeAndPassProposal(proposal);

        vm.expectRevert(
            abi.encodeWithSelector(
                ArbitraryCallsProposal.ArbitraryCallFailedError.selector,
                abi.encodePacked(PushDistributor.WrongMembers.selector)
            )
        );
        _executeProposal(proposalId, proposal);

        // Add the last member back and pass
        members.push(lastMember);

        proposal = _createProposal(ETH_ADDRESS, amountToDistribute);

        _proposePassAndExecuteProposal(proposal);
    }

    function test_distribute_cannotReenter() external {
        // Deploy a malicious contract that will attempt to re-enter the distribute function
        address reenteringMember = address(
            new ReenteringMember(address(pushDistributor), address(erc20), members, 1 ether)
        );

        // Add the malicious contract as a member to simulate a scenario where it can receive funds and re-enter
        _addMember(reenteringMember);

        uint256 amountToDistribute = 10e18;

        PartyGovernance.Proposal memory proposal = _createProposal(ETH_ADDRESS, amountToDistribute);

        _proposePassAndExecuteProposal(proposal);

        // Check if the distribution was successful
        // John, Danny, Steve who each have 100 / 401 voting power should
        // receive 100 / 401 * 10e18 ETH
        assertEq(john.balance, (100 * amountToDistribute) / 401);
        assertEq(danny.balance, (100 * amountToDistribute) / 401);
        assertEq(steve.balance, (100 * amountToDistribute) / 401);
        // The contract which has 1 / 401 voting power should receive
        // 1 / 401 * 10e18 ETH
        assertEq(address(this).balance, (1 * amountToDistribute) / 401);
        // The reentering member should not receive any ETH because their
        // re-entrancy attempt reverted
        assertEq(reenteringMember.balance, 0);
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

    function _addMember(address member) internal {
        // Update Party state
        party.increaseTotalVotingPower(100);
        party.mint(member, 100, member);

        members.push(member);

        // Sort the addresses from lowest to highest.
        for (uint256 i = 0; i < members.length; i++) {
            for (uint256 j = i + 1; j < members.length; j++) {
                if (members[i] > members[j]) {
                    (members[i], members[j]) = (members[j], members[i]);
                }
            }
        }
    }

    receive() external payable {}
}

contract CannotReceiveETH is ERC721Receiver {
    receive() external payable {
        revert("Cannot receive ETH");
    }
}

contract ReenteringMember is ERC721Receiver {
    PushDistributor public pushDistributor;
    IERC20 public token;
    address[] public members;
    uint256 public amount;

    constructor(
        address _pushDistributor,
        address _token,
        address[] memory _members,
        uint256 _amount
    ) {
        pushDistributor = PushDistributor(_pushDistributor);
        token = IERC20(_token);
        members = _members;
        amount = _amount;
    }

    // Fallback function used to attempt re-entrancy
    receive() external payable {
        // Should revert so params do not really matter
        pushDistributor.distribute(token, members, amount, 0);
    }
}
