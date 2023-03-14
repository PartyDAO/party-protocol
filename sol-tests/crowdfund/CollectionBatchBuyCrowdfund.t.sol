// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/crowdfund/CollectionBatchBuyCrowdfund.sol";
import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";
import "../../contracts/utils/Proxy.sol";

import "../DummyERC721.sol";
import "../TestUtils.sol";

import "./MockPartyFactory.sol";
import "./MockParty.sol";
import "./TestERC721Vault.sol";

contract CollectionBatchBuyCrowdfundTest is Test, TestUtils {
    event MockPartyFactoryCreateParty(
        address caller,
        address authority,
        Party.PartyOptions opts,
        IERC721[] preciousTokens,
        uint256[] preciousTokenIds
    );

    Globals globals;
    DummyERC721 nftContract;
    DummyBatchMinter batchMinter;
    MockParty party;

    uint96 maximumPrice = 100e18;
    Crowdfund.FixedGovernanceOpts govOpts;

    constructor() {
        globals = new Globals(address(this));
        MockPartyFactory partyFactory = new MockPartyFactory();
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        party = partyFactory.mockParty();

        nftContract = new DummyERC721();
        batchMinter = new DummyBatchMinter();

        govOpts.hosts.push(address(this));
    }

    function _createCrowdfund(
        bytes32 nftTokenIdsMerkleRoot
    ) internal returns (CollectionBatchBuyCrowdfund cf) {
        cf = CollectionBatchBuyCrowdfund(
            payable(
                address(
                    new Proxy(
                        new CollectionBatchBuyCrowdfund(globals),
                        abi.encodeCall(
                            CollectionBatchBuyCrowdfund.initialize,
                            CollectionBatchBuyCrowdfund.CollectionBatchBuyCrowdfundOptions({
                                name: "Crowdfund",
                                symbol: "CF",
                                customizationPresetId: 0,
                                nftContract: nftContract,
                                nftTokenIdsMerkleRoot: nftTokenIdsMerkleRoot,
                                duration: 1 days,
                                maximumPrice: maximumPrice,
                                splitRecipient: payable(address(0)),
                                splitBps: 0,
                                initialContributor: address(0),
                                initialDelegate: address(0),
                                minContribution: 0,
                                maxContribution: type(uint96).max,
                                gateKeeper: IGateKeeper(address(0)),
                                gateKeeperId: 0,
                                governanceOpts: govOpts
                            })
                        )
                    )
                )
            )
        );
    }

    function _createCrowdfund() internal returns (CollectionBatchBuyCrowdfund cf) {
        return _createCrowdfund(bytes32(0));
    }

    function test_cannotReinitialize() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        vm.expectRevert(abi.encodeWithSelector(Implementation.OnlyConstructorError.selector));
        CollectionBatchBuyCrowdfund.CollectionBatchBuyCrowdfundOptions memory opts;
        cf.initialize(opts);
    }

    function test_happyPath() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(delegate, "");
        // Setup parameters to batch buy.
        IERC721[] memory tokens = new IERC721[](3);
        uint256[] memory tokenIds = new uint256[](3);
        CollectionBatchBuyCrowdfund.BuyCall[]
            memory calls = new CollectionBatchBuyCrowdfund.BuyCall[](3);
        for (uint256 i; i < calls.length; ++i) {
            tokens[i] = nftContract;
            tokenIds[i] = i + 1;

            CollectionBatchBuyCrowdfund.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyCrowdfund.TokenToBuy[](1);
            tokensToBuy[0].tokenId = i + 1;
            tokensToBuy[0].price = 1;

            calls[i] = CollectionBatchBuyCrowdfund.BuyCall({
                target: payable(address(nftContract)),
                data: abi.encodeCall(nftContract.mint, (address(cf))),
                tokensToBuy: tokensToBuy
            });
        }
        // Buy the tokens.
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryCreateParty(
            address(cf),
            address(cf),
            Party.PartyOptions({
                name: "Crowdfund",
                symbol: "CF",
                customizationPresetId: 0,
                governance: PartyGovernance.GovernanceOpts({
                    hosts: govOpts.hosts,
                    voteDuration: govOpts.voteDuration,
                    executionDelay: govOpts.executionDelay,
                    passThresholdBps: govOpts.passThresholdBps,
                    totalVotingPower: 3,
                    feeBps: govOpts.feeBps,
                    feeRecipient: govOpts.feeRecipient
                })
            }),
            tokens,
            tokenIds
        );
        Party party_ = cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: calls,
                numOfTokens: tokenIds.length,
                minTokensBought: tokenIds.length,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
        assertEq(address(party_), address(party));
    }

    function test_batchBuy_belowMinTokensBought() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(delegate, "");
        // Setup parameters to batch buy.
        IERC721[] memory tokens = new IERC721[](3);
        CollectionBatchBuyCrowdfund.BuyCall[]
            memory calls = new CollectionBatchBuyCrowdfund.BuyCall[](3);
        for (uint256 i; i < calls.length; ++i) {
            tokens[i] = nftContract;

            CollectionBatchBuyCrowdfund.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyCrowdfund.TokenToBuy[](1);
            tokensToBuy[0].tokenId = i + 1;
            tokensToBuy[0].price = 1;

            // Ensure the last call will fail to buy a token.
            if (i != calls.length - 1) {
                calls[i] = CollectionBatchBuyCrowdfund.BuyCall({
                    target: payable(address(nftContract)),
                    data: abi.encodeCall(nftContract.mint, (address(cf))),
                    tokensToBuy: tokensToBuy
                });
            }
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionBatchBuyCrowdfund.NotEnoughTokensBoughtError.selector,
                2,
                3
            )
        );
        // Buy the tokens.
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: calls,
                numOfTokens: tokens.length,
                minTokensBought: tokens.length,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }

    function test_batchBuy_belowMinEthUsed() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(delegate, "");
        // Setup parameters to batch buy.
        IERC721[] memory tokens = new IERC721[](3);
        CollectionBatchBuyCrowdfund.BuyCall[]
            memory calls = new CollectionBatchBuyCrowdfund.BuyCall[](3);
        for (uint256 i; i < calls.length; ++i) {
            tokens[i] = nftContract;

            CollectionBatchBuyCrowdfund.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyCrowdfund.TokenToBuy[](1);
            tokensToBuy[0].tokenId = i + 1;
            tokensToBuy[0].price = 1;

            calls[i] = CollectionBatchBuyCrowdfund.BuyCall({
                target: payable(address(nftContract)),
                data: abi.encodeCall(nftContract.mint, (address(cf))),
                tokensToBuy: tokensToBuy
            });
        }
        // Buy the tokens.
        vm.expectRevert(
            abi.encodeWithSelector(CollectionBatchBuyCrowdfund.NotEnoughEthUsedError.selector, 3, 4)
        );
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: calls,
                numOfTokens: tokens.length,
                minTokensBought: tokens.length,
                minTotalEthUsed: 4,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }

    function test_batchBuy_updatedTokenLength() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(delegate, "");
        // Setup parameters to batch buy.
        CollectionBatchBuyCrowdfund.BuyCall[]
            memory calls = new CollectionBatchBuyCrowdfund.BuyCall[](3);
        for (uint256 i; i < calls.length; ++i) {
            // Ensure one token will fail to be bought
            if (i == 1) continue;

            CollectionBatchBuyCrowdfund.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyCrowdfund.TokenToBuy[](1);
            tokensToBuy[0].tokenId = i == 0 ? 1 : 2;
            tokensToBuy[0].price = 1;

            calls[i] = CollectionBatchBuyCrowdfund.BuyCall({
                target: payable(address(nftContract)),
                data: abi.encodeCall(nftContract.mint, (address(cf))),
                tokensToBuy: tokensToBuy
            });
        }
        // Check that token length is updated from 3 to 2 when creating the party
        IERC721[] memory tokens = new IERC721[](2);
        uint256[] memory tokenIds = new uint256[](2);
        for (uint256 i; i < tokenIds.length; i++) {
            tokens[i] = nftContract;
            tokenIds[i] = i + 1;
        }
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryCreateParty(
            address(cf),
            address(cf),
            Party.PartyOptions({
                name: "Crowdfund",
                symbol: "CF",
                customizationPresetId: 0,
                governance: PartyGovernance.GovernanceOpts({
                    hosts: govOpts.hosts,
                    voteDuration: govOpts.voteDuration,
                    executionDelay: govOpts.executionDelay,
                    passThresholdBps: govOpts.passThresholdBps,
                    totalVotingPower: 2,
                    feeBps: govOpts.feeBps,
                    feeRecipient: govOpts.feeRecipient
                })
            }),
            tokens,
            tokenIds
        );
        // Buy the tokens.
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: calls,
                numOfTokens: 2,
                minTokensBought: tokenIds.length - 1,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }

    function test_batchBuy_cannotMinTokensBoughtZero() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        // Buy the tokens.
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionBatchBuyCrowdfund.InvalidMinTokensBoughtError.selector,
                0
            )
        );
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: new CollectionBatchBuyCrowdfund.BuyCall[](0),
                numOfTokens: 0,
                minTokensBought: 0,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }

    function test_batchBuy_cannotTriggerLostByNotBuyingAnything() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        // Buy the tokens.
        vm.expectRevert(CollectionBatchBuyCrowdfund.NothingBoughtError.selector);
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: new CollectionBatchBuyCrowdfund.BuyCall[](0),
                numOfTokens: 1,
                minTokensBought: 1,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }

    function test_batchBuy_cannotTriggerLostByBuyingFreeNFTs() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        // Setup parameters to batch buy.
        CollectionBatchBuyCrowdfund.BuyCall[]
            memory calls = new CollectionBatchBuyCrowdfund.BuyCall[](3);
        for (uint256 i; i < calls.length; ++i) {
            CollectionBatchBuyCrowdfund.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyCrowdfund.TokenToBuy[](1);
            tokensToBuy[0].tokenId = i + 1;

            calls[i].tokensToBuy = tokensToBuy;

            // Mint tokens to crowdfund for free.
            nftContract.mint(address(cf));
        }
        // Buy the tokens.
        vm.expectRevert(CollectionBatchBuyCrowdfund.NothingBoughtError.selector);
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: calls,
                numOfTokens: 3,
                minTokensBought: 3,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }

    function test_batchBuy_failedBuyCannotUseETH() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(delegate, "");
        // Setup parameters to batch buy.
        CollectionBatchBuyCrowdfund.BuyCall[]
            memory calls = new CollectionBatchBuyCrowdfund.BuyCall[](2);
        for (uint256 i; i < calls.length; ++i) {
            CollectionBatchBuyCrowdfund.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyCrowdfund.TokenToBuy[](1);
            // Spend ETH on this failed buy.
            tokensToBuy[0].price = 1e18;
            calls[i].tokensToBuy = tokensToBuy;
        }
        // Buy the tokens.
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionBatchBuyCrowdfund.EthUsedForFailedBuyError.selector,
                0,
                1e18
            )
        );
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: calls,
                numOfTokens: 2,
                minTokensBought: 1,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }

    function test_batchBuy_aboveMaximumPrice() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        // Setup parameters to batch buy.
        CollectionBatchBuyCrowdfund.BuyCall[]
            memory calls = new CollectionBatchBuyCrowdfund.BuyCall[](1);
        CollectionBatchBuyCrowdfund.TokenToBuy[]
            memory tokensToBuy = new CollectionBatchBuyCrowdfund.TokenToBuy[](1);
        tokensToBuy[0].tokenId = 1;
        // Set the price to be above the maximum price.
        tokensToBuy[0].price = maximumPrice + 1;
        calls[0] = CollectionBatchBuyCrowdfund.BuyCall({
            target: payable(address(nftContract)),
            data: abi.encodeCall(nftContract.mint, (address(cf))),
            tokensToBuy: tokensToBuy
        });
        // Buy the tokens.
        vm.expectRevert(
            abi.encodeWithSelector(
                BuyCrowdfundBase.MaximumPriceError.selector,
                maximumPrice + 1,
                maximumPrice
            )
        );
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: calls,
                numOfTokens: 1,
                minTokensBought: 1,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }

    function test_batchBuy_onlyHost() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        // Setup parameters to batch buy.
        CollectionBatchBuyCrowdfund.BuyCall[]
            memory calls = new CollectionBatchBuyCrowdfund.BuyCall[](3);
        for (uint256 i; i < calls.length; ++i) {
            CollectionBatchBuyCrowdfund.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyCrowdfund.TokenToBuy[](1);
            tokensToBuy[0].tokenId = i + 1;
            calls[i] = CollectionBatchBuyCrowdfund.BuyCall({
                target: payable(address(nftContract)),
                data: abi.encodeCall(nftContract.mint, (address(cf))),
                tokensToBuy: tokensToBuy
            });
        }
        // Buy the tokens.
        vm.prank(_randomAddress());
        vm.expectRevert(Crowdfund.OnlyPartyHostError.selector);
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: calls,
                numOfTokens: 3,
                minTokensBought: 3,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }

    function test_batchBuy_invalidGovOpts() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        // Setup parameters to batch buy.
        CollectionBatchBuyCrowdfund.BuyCall[]
            memory calls = new CollectionBatchBuyCrowdfund.BuyCall[](3);
        for (uint256 i; i < calls.length; ++i) {
            CollectionBatchBuyCrowdfund.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyCrowdfund.TokenToBuy[](1);
            tokensToBuy[0].tokenId = i + 1;
            tokensToBuy[0].price = 0;
            calls[i] = CollectionBatchBuyCrowdfund.BuyCall({
                target: payable(address(nftContract)),
                data: abi.encodeCall(nftContract.mint, (address(cf))),
                tokensToBuy: tokensToBuy
            });
        }
        // Mutate governance options
        govOpts.hosts.push(_randomAddress());
        // Buy the tokens.
        vm.expectRevert(Crowdfund.InvalidGovernanceOptionsError.selector);
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: calls,
                numOfTokens: 3,
                minTokensBought: 3,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }

    function test_batchBuy_withTokenIdsAllowList() public {
        uint256 tokenId = 1;
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund(keccak256(abi.encodePacked(tokenId)));
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(contributor, "");
        // Setup parameters to batch buy.
        CollectionBatchBuyCrowdfund.BuyCall[]
            memory calls = new CollectionBatchBuyCrowdfund.BuyCall[](1);
        CollectionBatchBuyCrowdfund.TokenToBuy[]
            memory tokensToBuy = new CollectionBatchBuyCrowdfund.TokenToBuy[](1);
        tokensToBuy[0].tokenId = tokenId;
        tokensToBuy[0].price = 1;
        calls[0] = CollectionBatchBuyCrowdfund.BuyCall({
            target: payable(address(nftContract)),
            data: abi.encodeCall(nftContract.mint, (address(cf))),
            tokensToBuy: tokensToBuy
        });
        // Buy the tokens.
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: calls,
                numOfTokens: 1,
                minTokensBought: 1,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }

    function test_batchBuy_withTokenIdsAllowList_invalidProof() public {
        uint256 tokenId = 1;
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund(keccak256(abi.encodePacked(tokenId)));
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(contributor, "");
        // Setup parameters to batch buy.
        CollectionBatchBuyCrowdfund.BuyCall[]
            memory calls = new CollectionBatchBuyCrowdfund.BuyCall[](1);
        CollectionBatchBuyCrowdfund.TokenToBuy[]
            memory tokensToBuy = new CollectionBatchBuyCrowdfund.TokenToBuy[](1);
        tokensToBuy[0].tokenId = tokenId;
        tokensToBuy[0].price = 1;
        tokensToBuy[0].proof = new bytes32[](1);
        calls[0] = CollectionBatchBuyCrowdfund.BuyCall({
            target: payable(address(nftContract)),
            data: abi.encodeCall(nftContract.mint, (address(cf))),
            tokensToBuy: tokensToBuy
        });
        // Buy the tokens.
        vm.expectRevert(CollectionBatchBuyCrowdfund.InvalidTokenIdError.selector);
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: calls,
                numOfTokens: 1,
                minTokensBought: 1,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }

    function test_batchBuy_multipleTokensBoughtPerCall() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        // Contribute and delegate.
        address payable contributor = _randomAddress();
        address delegate = _randomAddress();
        vm.deal(contributor, 1e18);
        vm.prank(contributor);
        cf.contribute{ value: contributor.balance }(delegate, "");
        // Setup parameters to batch buy.
        IERC721[] memory tokens = new IERC721[](6);
        uint256[] memory tokenIds = new uint256[](6);
        CollectionBatchBuyCrowdfund.BuyCall[]
            memory calls = new CollectionBatchBuyCrowdfund.BuyCall[](2);
        for (uint256 i = 0; i < calls.length; ++i) {
            CollectionBatchBuyCrowdfund.TokenToBuy[]
                memory tokensToBuy = new CollectionBatchBuyCrowdfund.TokenToBuy[](3);
            for (uint256 j = 0; j < tokensToBuy.length; ++j) {
                uint256 tokenId = i * tokensToBuy.length + j + 1;
                tokens[tokenId - 1] = nftContract;
                tokensToBuy[j].tokenId = tokenIds[tokenId - 1] = tokenId;
                tokensToBuy[j].price = 1;
            }
            calls[i] = CollectionBatchBuyCrowdfund.BuyCall({
                target: payable(address(batchMinter)),
                data: abi.encodeCall(batchMinter.batchMint, (nftContract, 3)),
                tokensToBuy: tokensToBuy
            });
        }
        vm.expectEmit(false, false, false, true);
        emit MockPartyFactoryCreateParty(
            address(cf),
            address(cf),
            Party.PartyOptions({
                name: "Crowdfund",
                symbol: "CF",
                customizationPresetId: 0,
                governance: PartyGovernance.GovernanceOpts({
                    hosts: govOpts.hosts,
                    voteDuration: govOpts.voteDuration,
                    executionDelay: govOpts.executionDelay,
                    passThresholdBps: govOpts.passThresholdBps,
                    totalVotingPower: 6,
                    feeBps: govOpts.feeBps,
                    feeRecipient: govOpts.feeRecipient
                })
            }),
            tokens,
            tokenIds
        );
        // Buy the tokens.
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                calls: calls,
                numOfTokens: 6,
                minTokensBought: 6,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }
}

contract DummyBatchMinter {
    function batchMint(DummyERC721 nftContract, uint256 tokensToMint) public payable {
        for (uint256 i; i < tokensToMint; ++i) {
            nftContract.mint(msg.sender);
        }
    }
}
