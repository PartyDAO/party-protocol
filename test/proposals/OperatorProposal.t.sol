// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/proposals/OperatorProposal.sol";
import "../../contracts/tokens/ERC721Receiver.sol";
import "../../contracts/tokens/ERC1155Receiver.sol";

import "../DummyERC20.sol";
import "../DummyERC721.sol";
import "../DummyERC1155.sol";
import "../TestUtils.sol";

contract TestableOperatorProposal is OperatorProposal, ERC721Receiver, ERC1155Receiver {
    function supportsInterface(
        bytes4 interfaceId
    ) public pure override(ERC721Receiver, ERC1155Receiver) returns (bool) {
        return
            ERC721Receiver.supportsInterface(interfaceId) ||
            ERC1155Receiver.supportsInterface(interfaceId);
    }

    function execute(
        IProposalExecutionEngine.ExecuteProposalParams calldata params
    ) external payable returns (bytes memory nextProgressData) {
        nextProgressData = _executeOperation(params);
    }
}

contract MockOperator is IOperator, ERC721Receiver, ERC1155Receiver {
    event OperationExecuted(address caller, bytes data, bytes executionData);

    function supportsInterface(
        bytes4 interfaceId
    ) public pure override(ERC721Receiver, ERC1155Receiver) returns (bool) {
        return
            ERC721Receiver.supportsInterface(interfaceId) ||
            ERC1155Receiver.supportsInterface(interfaceId);
    }

    function execute(
        bytes calldata data,
        bytes calldata executionData,
        address
    ) external payable override {
        emit OperationExecuted(msg.sender, data, executionData);
    }
}

contract OperatorProposalTest is Test, TestUtils {
    event OperationExecuted(address caller, bytes data, bytes executionData);

    TestableOperatorProposal operatorProposal;
    MockOperator mockOperator;
    DummyERC20 erc20;
    DummyERC721 erc721;
    DummyERC1155 erc1155;

    constructor() {
        operatorProposal = new TestableOperatorProposal();
        mockOperator = new MockOperator();
        erc20 = new DummyERC20();
        erc721 = new DummyERC721();
        erc1155 = new DummyERC1155();
    }

    function test_executeOperation() public {
        // Prepare the operator proposal data.
        address[] memory allowedExecutors = new address[](1);
        allowedExecutors[0] = address(this);

        OperatorProposal.AssetData[] memory assets = new OperatorProposal.AssetData[](0);

        OperatorProposal.OperatorProposalData memory data = OperatorProposal.OperatorProposalData({
            allowedExecutors: allowedExecutors,
            assets: assets,
            operator: IOperator(address(mockOperator)),
            operatorData: "0x1234"
        });

        // Execute the proposal.  vm.expectEmit(false, false, false, true);
        emit OperationExecuted(address(operatorProposal), "0x1234", "0x5678");
        bytes memory nextProgressData = operatorProposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: abi.encode(uint256(0), "0x5678"),
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            })
        );
        assertEq(nextProgressData.length, 0);
    }

    function test_executeOperation_withETH() public {
        // Prepare the operator proposal data.
        address[] memory allowedExecutors = new address[](1);
        allowedExecutors[0] = address(this);

        OperatorProposal.AssetData[] memory assets = new OperatorProposal.AssetData[](1);
        assets[0] = OperatorProposal.AssetData({
            tokenType: OperatorProposal.OperatorTokenType.ETH,
            token: address(0),
            tokenId: 0,
            amount: 1 ether
        });

        OperatorProposal.OperatorProposalData memory data = OperatorProposal.OperatorProposalData({
            allowedExecutors: allowedExecutors,
            assets: assets,
            operator: IOperator(address(mockOperator)),
            operatorData: "0x1234"
        });

        assertEq(address(mockOperator).balance, 0);

        // Execute the operation
        vm.deal(address(operatorProposal), 1 ether);
        operatorProposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: abi.encode(uint256(0), "0x5678"),
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            })
        );

        assertEq(address(mockOperator).balance, 1 ether);
    }

    function test_executeOperation_withERC20() public {
        // Prepare the operator proposal data.
        address[] memory allowedExecutors = new address[](1);
        allowedExecutors[0] = address(this);

        OperatorProposal.AssetData[] memory assets = new OperatorProposal.AssetData[](1);
        assets[0] = OperatorProposal.AssetData({
            tokenType: OperatorProposal.OperatorTokenType.ERC20,
            token: address(erc20),
            tokenId: 0,
            amount: 100e18
        });

        OperatorProposal.OperatorProposalData memory data = OperatorProposal.OperatorProposalData({
            allowedExecutors: allowedExecutors,
            assets: assets,
            operator: IOperator(address(mockOperator)),
            operatorData: "0x1234"
        });

        assertEq(erc20.balanceOf(address(mockOperator)), 0);

        // Execute the operation
        erc20.deal(address(operatorProposal), 100e18);
        operatorProposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: abi.encode(uint256(0), "0x5678"),
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            })
        );

        assertEq(erc20.balanceOf(address(mockOperator)), 100e18);
    }

    function test_executeOperation_withERC721() public {
        // Prepare the operator proposal data.
        address[] memory allowedExecutors = new address[](1);
        allowedExecutors[0] = address(this);

        OperatorProposal.AssetData[] memory assets = new OperatorProposal.AssetData[](1);
        assets[0] = OperatorProposal.AssetData({
            tokenType: OperatorProposal.OperatorTokenType.ERC721,
            token: address(erc721),
            tokenId: 1,
            amount: 1
        });

        OperatorProposal.OperatorProposalData memory data = OperatorProposal.OperatorProposalData({
            allowedExecutors: allowedExecutors,
            assets: assets,
            operator: IOperator(address(mockOperator)),
            operatorData: "0x1234"
        });

        assertEq(erc721.balanceOf(address(mockOperator)), 0);

        // Execute the operation
        erc721.mint(address(operatorProposal));
        operatorProposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: abi.encode(uint256(0), "0x5678"),
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            })
        );

        assertEq(erc721.balanceOf(address(mockOperator)), 1);
    }

    function test_executeOperation_withERC1155() public {
        // Prepare the operator proposal data.
        address[] memory allowedExecutors = new address[](1);
        allowedExecutors[0] = address(this);

        OperatorProposal.AssetData[] memory assets = new OperatorProposal.AssetData[](1);
        assets[0] = OperatorProposal.AssetData({
            tokenType: OperatorProposal.OperatorTokenType.ERC1155,
            token: address(erc1155),
            tokenId: 1,
            amount: 10
        });

        OperatorProposal.OperatorProposalData memory data = OperatorProposal.OperatorProposalData({
            allowedExecutors: allowedExecutors,
            assets: assets,
            operator: IOperator(address(mockOperator)),
            operatorData: "0x1234"
        });

        assertEq(erc1155.balanceOf(address(mockOperator), 1), 0);

        // Execute the operation
        erc1155.deal(address(operatorProposal), 1, 10);
        operatorProposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: abi.encode(uint256(0), "0x5678"),
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            })
        );

        assertEq(erc1155.balanceOf(address(mockOperator), 1), 10);
    }

    function test_executeOperation_withMixedAssets() public {
        // Prepare the operator proposal data.
        address[] memory allowedExecutors = new address[](1);
        allowedExecutors[0] = address(this);

        OperatorProposal.AssetData[] memory assets = new OperatorProposal.AssetData[](4);
        assets[0] = OperatorProposal.AssetData({
            tokenType: OperatorProposal.OperatorTokenType.ETH,
            token: address(0),
            tokenId: 0,
            amount: 1 ether
        });
        assets[1] = OperatorProposal.AssetData({
            tokenType: OperatorProposal.OperatorTokenType.ERC20,
            token: address(erc20),
            tokenId: 0,
            amount: 100e18
        });
        assets[2] = OperatorProposal.AssetData({
            tokenType: OperatorProposal.OperatorTokenType.ERC721,
            token: address(erc721),
            tokenId: 1,
            amount: 1
        });
        assets[3] = OperatorProposal.AssetData({
            tokenType: OperatorProposal.OperatorTokenType.ERC1155,
            token: address(erc1155),
            tokenId: 1,
            amount: 10
        });

        OperatorProposal.OperatorProposalData memory data = OperatorProposal.OperatorProposalData({
            allowedExecutors: allowedExecutors,
            assets: assets,
            operator: IOperator(address(mockOperator)),
            operatorData: "0x1234"
        });

        assertEq(address(mockOperator).balance, 0);
        assertEq(erc20.balanceOf(address(mockOperator)), 0);
        assertEq(erc721.balanceOf(address(mockOperator)), 0);
        assertEq(erc1155.balanceOf(address(mockOperator), 1), 0);

        // Execute the operation
        vm.deal(address(operatorProposal), 1 ether);
        erc20.deal(address(operatorProposal), 100e18);
        erc721.mint(address(operatorProposal));
        erc1155.deal(address(operatorProposal), 1, 10);
        operatorProposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: abi.encode(uint256(0), "0x5678"),
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            })
        );

        assertEq(address(mockOperator).balance, 1 ether);
        assertEq(erc20.balanceOf(address(mockOperator)), 100e18);
        assertEq(erc721.balanceOf(address(mockOperator)), 1);
        assertEq(erc1155.balanceOf(address(mockOperator), 1), 10);
    }

    function test_executeOperation_onlyAllowedExecutor() public {
        // Prepare the operator proposal data.
        address[] memory allowedExecutors = new address[](1);
        allowedExecutors[0] = address(this);

        OperatorProposal.AssetData[] memory assets = new OperatorProposal.AssetData[](0);

        OperatorProposal.OperatorProposalData memory data = OperatorProposal.OperatorProposalData({
            allowedExecutors: allowedExecutors,
            assets: assets,
            operator: IOperator(address(mockOperator)),
            operatorData: "0x1234"
        });

        // Execute the proposal.
        address notAllowedExecutor = _randomAddress();
        vm.prank(notAllowedExecutor);
        vm.expectRevert(
            abi.encodeWithSelector(
                OperatorProposal.NotAllowedToExecute.selector,
                notAllowedExecutor,
                allowedExecutors
            )
        );
        bytes memory nextProgressData = operatorProposal.execute(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: abi.encode(uint256(0), "0x5678"),
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(data)
            })
        );
        assertEq(nextProgressData.length, 0);
    }
}
