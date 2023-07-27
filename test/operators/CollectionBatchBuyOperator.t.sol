// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "contracts/operators/CollectionBatchBuyOperator.sol";
import "contracts/tokens/ERC721Receiver.sol";

import "../DummyERC721.sol";
import "../TestUtils.sol";

contract CollectionBatchBuyOperatorTest is Test, TestUtils, ERC721Receiver {
    event CollectionBatchBuyOperationExecuted(
        Party party,
        IERC721 token,
        uint256[] tokenIdsBought,
        uint256 totalEthUsed
    );

    CollectionBatchBuyOperator operator;
    DummyBatchMinter batchMinter;
    DummyERC721 nftContract;

    uint96 maximumPrice = 100e18;

    constructor() {
        operator = new CollectionBatchBuyOperator();
        nftContract = new DummyERC721();
        batchMinter = new DummyBatchMinter();

        vm.deal(address(this), type(uint256).max);
    }

    receive() external payable {}

    function test_onERC721Received_works() public {
        // Test transferring an NFT to the operator.
        uint256 tokenId = nftContract.mint(address(this));

        // Transfer the NFT to the operator.
        nftContract.safeTransferFrom(address(this), address(operator), tokenId);

        // Ensure the operator received the NFT.
        assertEq(nftContract.ownerOf(tokenId), address(operator));
    }

    function test_execute_works() public {
        // Setup the operation
        CollectionBatchBuyOperator.BuyCall[]
            memory calls = new CollectionBatchBuyOperator.BuyCall[](3);
        for (uint256 i; i < calls.length; ++i) {
            CollectionBatchBuyOperator.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyOperator.TokenToBuy[](1);
            tokensToBuy[0].tokenId = i + 1;
            tokensToBuy[0].price = 1;

            calls[i] = CollectionBatchBuyOperator.BuyCall({
                target: payable(address(nftContract)),
                data: abi.encodeCall(nftContract.mint, (address(operator))),
                tokensToBuy: tokensToBuy
            });
        }

        bytes memory operatorData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyOperationData({
                nftContract: IERC721(address(nftContract)),
                nftTokenIdsMerkleRoot: bytes32(0),
                maximumPrice: maximumPrice,
                minTokensBought: 3,
                minTotalEthUsed: 0
            })
        );
        bytes memory executionData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyExecutionData({
                calls: calls,
                numOfTokens: 3,
                isReceivedDirectly: false
            })
        );

        // Execute the operation
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;
        vm.expectEmit(false, false, false, true);
        emit CollectionBatchBuyOperationExecuted(
            Party(payable(address(this))),
            nftContract,
            tokenIds,
            3
        );

        uint256 balanceBefore = address(this).balance;
        operator.execute{ value: 5 }(operatorData, executionData, _randomAddress());
        assertEq(balanceBefore - address(this).balance, 3); // Sent 5 wei, only used 3 wei
        for (uint256 i; i < tokenIds.length; ++i) {
            assertEq(nftContract.ownerOf(tokenIds[i]), address(this));
        }
    }

    function test_execute_canReceiveDirectly() public {
        // Setup the operation
        CollectionBatchBuyOperator.BuyCall[]
            memory calls = new CollectionBatchBuyOperator.BuyCall[](3);
        for (uint256 i; i < calls.length; ++i) {
            CollectionBatchBuyOperator.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyOperator.TokenToBuy[](1);
            tokensToBuy[0].tokenId = i + 1;
            tokensToBuy[0].price = 1;

            calls[i] = CollectionBatchBuyOperator.BuyCall({
                target: payable(address(nftContract)),
                data: abi.encodeCall(nftContract.mint, (address(this))),
                tokensToBuy: tokensToBuy
            });
        }

        bytes memory operatorData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyOperationData({
                nftContract: IERC721(address(nftContract)),
                nftTokenIdsMerkleRoot: bytes32(0),
                maximumPrice: maximumPrice,
                minTokensBought: 3,
                minTotalEthUsed: 0
            })
        );
        bytes memory executionData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyExecutionData({
                calls: calls,
                numOfTokens: 3,
                isReceivedDirectly: true
            })
        );

        // Execute the operation
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;
        vm.expectEmit(false, false, false, true);
        emit CollectionBatchBuyOperationExecuted(
            Party(payable(address(this))),
            nftContract,
            tokenIds,
            3
        );

        uint256 balanceBefore = address(this).balance;
        operator.execute{ value: 5 }(operatorData, executionData, _randomAddress());
        assertEq(balanceBefore - address(this).balance, 3); // Sent 5 wei, only used 3 wei
        for (uint256 i; i < tokenIds.length; ++i) {
            assertEq(nftContract.ownerOf(tokenIds[i]), address(this));
        }
    }

    function test_execute_belowMinTokensBought() public {
        // Setup the operation
        CollectionBatchBuyOperator.BuyCall[]
            memory calls = new CollectionBatchBuyOperator.BuyCall[](3);
        for (uint256 i; i < calls.length; ++i) {
            CollectionBatchBuyOperator.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyOperator.TokenToBuy[](1);
            tokensToBuy[0].tokenId = i + 1;
            tokensToBuy[0].price = 1;

            // Ensure the last call will fail to buy a token.
            if (i != calls.length - 1) {
                calls[i] = CollectionBatchBuyOperator.BuyCall({
                    target: payable(address(nftContract)),
                    data: abi.encodeCall(nftContract.mint, (address(operator))),
                    tokensToBuy: tokensToBuy
                });
            }
        }
        bytes memory operatorData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyOperationData({
                nftContract: IERC721(address(nftContract)),
                nftTokenIdsMerkleRoot: bytes32(0),
                maximumPrice: maximumPrice,
                minTokensBought: 3,
                minTotalEthUsed: 0
            })
        );
        bytes memory executionData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyExecutionData({
                calls: calls,
                numOfTokens: 3,
                isReceivedDirectly: false
            })
        );

        // Execute the operation
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionBatchBuyOperator.NotEnoughTokensBoughtError.selector,
                2,
                3
            )
        );
        operator.execute{ value: 3 }(operatorData, executionData, _randomAddress());
    }

    function test_execute_updatedTokenLength() public {
        // Setup the operation
        CollectionBatchBuyOperator.BuyCall[]
            memory calls = new CollectionBatchBuyOperator.BuyCall[](3);
        for (uint256 i; i < calls.length; ++i) {
            // Ensure one token will fail to be bought
            if (i == 1) continue;

            CollectionBatchBuyOperator.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyOperator.TokenToBuy[](1);
            tokensToBuy[0].tokenId = i == 0 ? 1 : 2;
            tokensToBuy[0].price = 1;

            calls[i] = CollectionBatchBuyOperator.BuyCall({
                target: payable(address(nftContract)),
                data: abi.encodeCall(nftContract.mint, (address(operator))),
                tokensToBuy: tokensToBuy
            });
        }

        bytes memory operatorData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyOperationData({
                nftContract: IERC721(address(nftContract)),
                nftTokenIdsMerkleRoot: bytes32(0),
                maximumPrice: maximumPrice,
                minTokensBought: 2,
                minTotalEthUsed: 0
            })
        );
        bytes memory executionData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyExecutionData({
                calls: calls,
                numOfTokens: 3,
                isReceivedDirectly: false
            })
        );

        // Execute the operation
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        vm.expectEmit(false, false, false, true);
        emit CollectionBatchBuyOperationExecuted(
            Party(payable(address(this))),
            nftContract,
            tokenIds,
            2
        );
        operator.execute{ value: 2 }(operatorData, executionData, _randomAddress());
    }

    function test_execute_cannotMinTokensBoughtZero() public {
        // Prepare the operation data
        bytes memory operatorData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyOperationData({
                nftContract: IERC721(address(nftContract)),
                nftTokenIdsMerkleRoot: bytes32(0),
                maximumPrice: maximumPrice,
                minTokensBought: 0,
                minTotalEthUsed: 0
            })
        );
        bytes memory executionData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyExecutionData({
                calls: new CollectionBatchBuyOperator.BuyCall[](0),
                numOfTokens: 0,
                isReceivedDirectly: false
            })
        );

        // Execute the operation
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionBatchBuyOperator.InvalidMinTokensBoughtError.selector,
                0
            )
        );
        operator.execute{ value: 0 }(operatorData, executionData, _randomAddress());
    }

    function test_execute_cannotBuyingNothing() public {
        // Prepare the operation data
        bytes memory operatorData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyOperationData({
                nftContract: IERC721(address(nftContract)),
                nftTokenIdsMerkleRoot: bytes32(0),
                maximumPrice: maximumPrice,
                minTokensBought: 1,
                minTotalEthUsed: 0
            })
        );
        bytes memory executionData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyExecutionData({
                calls: new CollectionBatchBuyOperator.BuyCall[](0),
                numOfTokens: 1,
                isReceivedDirectly: false
            })
        );

        // Execute the operation
        vm.expectRevert(CollectionBatchBuyOperator.NothingBoughtError.selector);
        operator.execute(operatorData, executionData, _randomAddress());
    }

    function test_execute_failedBuyCannotUseETH() public {
        // Setup the operation
        CollectionBatchBuyOperator.BuyCall[]
            memory calls = new CollectionBatchBuyOperator.BuyCall[](2);
        for (uint256 i; i < calls.length; ++i) {
            CollectionBatchBuyOperator.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyOperator.TokenToBuy[](1);
            // Spend ETH on this failed buy.
            tokensToBuy[0].price = 1e18;
            calls[i].tokensToBuy = tokensToBuy;
        }

        bytes memory operatorData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyOperationData({
                nftContract: IERC721(address(nftContract)),
                nftTokenIdsMerkleRoot: bytes32(0),
                maximumPrice: maximumPrice,
                minTokensBought: 1,
                minTotalEthUsed: 0
            })
        );
        bytes memory executionData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyExecutionData({
                calls: calls,
                numOfTokens: 2,
                isReceivedDirectly: false
            })
        );

        // Execute the operation
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionBatchBuyOperator.EthUsedForFailedBuyError.selector,
                0,
                1e18
            )
        );
        operator.execute{ value: 2e18 }(operatorData, executionData, _randomAddress());
    }

    function test_execute_aboveMaximumPrice() public {
        // Setup the operation
        CollectionBatchBuyOperator.BuyCall[]
            memory calls = new CollectionBatchBuyOperator.BuyCall[](1);
        CollectionBatchBuyOperator.TokenToBuy[]
            memory tokensToBuy = new CollectionBatchBuyOperator.TokenToBuy[](1);
        tokensToBuy[0].tokenId = 1;
        // Set the price to be above the maximum price.
        tokensToBuy[0].price = maximumPrice + 1;
        calls[0] = CollectionBatchBuyOperator.BuyCall({
            target: payable(address(nftContract)),
            data: abi.encodeCall(nftContract.mint, (address(operator))),
            tokensToBuy: tokensToBuy
        });

        bytes memory operatorData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyOperationData({
                nftContract: IERC721(address(nftContract)),
                nftTokenIdsMerkleRoot: bytes32(0),
                maximumPrice: maximumPrice,
                minTokensBought: 1,
                minTotalEthUsed: 0
            })
        );
        bytes memory executionData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyExecutionData({
                calls: calls,
                numOfTokens: 1,
                isReceivedDirectly: false
            })
        );

        // Execute the operation
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionBatchBuyOperator.MaximumPriceError.selector,
                maximumPrice + 1,
                maximumPrice
            )
        );
        operator.execute{ value: maximumPrice + 1 }(operatorData, executionData, _randomAddress());
    }

    function test_execute_withTokenIdsAllowList() public {
        uint256 tokenId = 1;

        // Setup the operation
        CollectionBatchBuyOperator.BuyCall[]
            memory calls = new CollectionBatchBuyOperator.BuyCall[](1);
        CollectionBatchBuyOperator.TokenToBuy[]
            memory tokensToBuy = new CollectionBatchBuyOperator.TokenToBuy[](1);
        tokensToBuy[0].tokenId = tokenId;
        tokensToBuy[0].price = 1;
        calls[0] = CollectionBatchBuyOperator.BuyCall({
            target: payable(address(nftContract)),
            data: abi.encodeCall(nftContract.mint, (address(operator))),
            tokensToBuy: tokensToBuy
        });

        bytes memory operatorData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyOperationData({
                nftContract: IERC721(address(nftContract)),
                nftTokenIdsMerkleRoot: keccak256(abi.encodePacked(tokenId)),
                maximumPrice: maximumPrice,
                minTokensBought: 1,
                minTotalEthUsed: 0
            })
        );
        bytes memory executionData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyExecutionData({
                calls: calls,
                numOfTokens: 1,
                isReceivedDirectly: false
            })
        );

        // Execute the operation
        operator.execute{ value: 1 }(operatorData, executionData, _randomAddress());
    }

    function test_execute_withTokenIdsAllowList_invalidProof() public {
        uint256 tokenId = 1;

        // Setup the operation
        CollectionBatchBuyOperator.BuyCall[]
            memory calls = new CollectionBatchBuyOperator.BuyCall[](1);
        CollectionBatchBuyOperator.TokenToBuy[]
            memory tokensToBuy = new CollectionBatchBuyOperator.TokenToBuy[](1);
        tokensToBuy[0].tokenId = tokenId;
        tokensToBuy[0].price = 1;
        tokensToBuy[0].proof = new bytes32[](1);
        calls[0] = CollectionBatchBuyOperator.BuyCall({
            target: payable(address(nftContract)),
            data: abi.encodeCall(nftContract.mint, (address(operator))),
            tokensToBuy: tokensToBuy
        });

        bytes memory operatorData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyOperationData({
                nftContract: IERC721(address(nftContract)),
                nftTokenIdsMerkleRoot: keccak256(abi.encodePacked(tokenId)),
                maximumPrice: maximumPrice,
                minTokensBought: 1,
                minTotalEthUsed: 0
            })
        );
        bytes memory executionData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyExecutionData({
                calls: calls,
                numOfTokens: 1,
                isReceivedDirectly: false
            })
        );

        // Execute the operation
        vm.expectRevert(CollectionBatchBuyOperator.InvalidTokenIdError.selector);
        operator.execute{ value: 1 }(operatorData, executionData, _randomAddress());
    }

    function test_execute_multipleTokensBoughtPerCall() public {
        // Setup the operation
        IERC721[] memory tokens = new IERC721[](6);
        uint256[] memory tokenIds = new uint256[](6);
        CollectionBatchBuyOperator.BuyCall[]
            memory calls = new CollectionBatchBuyOperator.BuyCall[](2);
        for (uint256 i = 0; i < calls.length; ++i) {
            CollectionBatchBuyOperator.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyOperator.TokenToBuy[](3);
            for (uint256 j = 0; j < tokensToBuy.length; ++j) {
                uint256 tokenId = i * tokensToBuy.length + j + 1;
                tokens[tokenId - 1] = nftContract;
                tokensToBuy[j].tokenId = tokenIds[tokenId - 1] = tokenId;
                tokensToBuy[j].price = 1;
            }
            calls[i] = CollectionBatchBuyOperator.BuyCall({
                target: payable(address(batchMinter)),
                data: abi.encodeCall(batchMinter.batchMint, (nftContract, 3)),
                tokensToBuy: tokensToBuy
            });
        }

        bytes memory operatorData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyOperationData({
                nftContract: IERC721(address(nftContract)),
                nftTokenIdsMerkleRoot: "",
                maximumPrice: maximumPrice,
                minTokensBought: 6,
                minTotalEthUsed: 0
            })
        );
        bytes memory executionData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyExecutionData({
                calls: calls,
                numOfTokens: 6,
                isReceivedDirectly: false
            })
        );

        // Execute the operation
        operator.execute{ value: 6 }(operatorData, executionData, _randomAddress());
    }

    /// @dev Tests that `execute` reverts if the tokens are not in ascending order per call.
    function test_execute_tokensMustBeSorted() public {
        CollectionBatchBuyOperator.BuyCall[]
            memory calls = new CollectionBatchBuyOperator.BuyCall[](1);

        CollectionBatchBuyOperator.TokenToBuy[]
            memory tokensToBuy = new CollectionBatchBuyOperator.TokenToBuy[](3);
        for (uint256 j = 0; j < tokensToBuy.length; ++j) {
            uint256 tokenId = 3 - j;
            tokensToBuy[j].tokenId = tokenId;
            tokensToBuy[j].price = 2;
        }
        calls[0] = CollectionBatchBuyOperator.BuyCall({
            target: payable(address(batchMinter)),
            data: abi.encodeCall(batchMinter.batchMint, (nftContract, 3)),
            tokensToBuy: tokensToBuy
        });

        bytes memory operatorData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyOperationData({
                nftContract: IERC721(address(nftContract)),
                nftTokenIdsMerkleRoot: "",
                maximumPrice: maximumPrice,
                minTokensBought: 3,
                minTotalEthUsed: 2
            })
        );
        bytes memory executionData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyExecutionData({
                calls: calls,
                numOfTokens: 3,
                isReceivedDirectly: false
            })
        );

        vm.expectRevert(CollectionBatchBuyOperator.TokenIdsNotSorted.selector);
        operator.execute{ value: 6 }(operatorData, executionData, _randomAddress());
    }

    /// @dev Tests that `execute` reverts if the token is already owned.
    function test_execute_tokenAlreadyOwned() public {
        CollectionBatchBuyOperator.BuyCall[]
            memory calls = new CollectionBatchBuyOperator.BuyCall[](2);

        {
            CollectionBatchBuyOperator.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyOperator.TokenToBuy[](1);

            tokensToBuy[0].tokenId = 1;
            tokensToBuy[0].price = 2;

            calls[0] = CollectionBatchBuyOperator.BuyCall({
                target: payable(address(batchMinter)),
                data: abi.encodeCall(batchMinter.batchMint, (nftContract, 1)),
                tokensToBuy: tokensToBuy
            });
        }
        {
            CollectionBatchBuyOperator.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyOperator.TokenToBuy[](1);

            tokensToBuy[0].tokenId = 1;
            tokensToBuy[0].price = 2;

            calls[1] = CollectionBatchBuyOperator.BuyCall({
                target: payable(address(batchMinter)),
                data: abi.encodeCall(batchMinter.batchMint, (nftContract, 1)),
                tokensToBuy: tokensToBuy
            });
        }

        bytes memory operatorData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyOperationData({
                nftContract: IERC721(address(nftContract)),
                nftTokenIdsMerkleRoot: "",
                maximumPrice: maximumPrice,
                minTokensBought: 1,
                minTotalEthUsed: 1
            })
        );
        bytes memory executionData = abi.encode(
            CollectionBatchBuyOperator.CollectionBatchBuyExecutionData({
                calls: calls,
                numOfTokens: 2,
                isReceivedDirectly: false
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionBatchBuyOperator.TokenAlreadyOwned.selector,
                nftContract,
                1
            )
        );
        operator.execute{ value: 6 }(operatorData, executionData, _randomAddress());
    }
}

contract DummyBatchMinter {
    function batchMint(DummyERC721 nftContract, uint256 tokensToMint) public payable {
        for (uint256 i; i < tokensToMint; ++i) {
            nftContract.mint(msg.sender);
        }
    }
}
