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
    MockParty party;

    uint96 maximumPrice = 100e18;
    Crowdfund.FixedGovernanceOpts govOpts;

    constructor() {
        globals = new Globals(address(this));
        MockPartyFactory partyFactory = new MockPartyFactory();
        globals.setAddress(LibGlobals.GLOBAL_PARTY_FACTORY, address(partyFactory));
        party = partyFactory.mockParty();

        nftContract = new DummyERC721();

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
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        bytes[] memory callDatas = new bytes[](3);
        bytes32[][] memory proofs = new bytes32[][](3);
        for (uint256 i; i < tokenIds.length; i++) {
            tokens[i] = nftContract;
            tokenIds[i] = i + 1;
            callTargets[i] = payable(address(nftContract));
            callValues[i] = 1;
            callDatas[i] = abi.encodeCall(nftContract.mint, (address(cf)));
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
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
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
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        bytes[] memory callDatas = new bytes[](3);
        bytes32[][] memory proofs = new bytes32[][](3);
        for (uint256 i; i < tokenIds.length; i++) {
            tokens[i] = nftContract;
            tokenIds[i] = i + 1;
            callTargets[i] = payable(address(nftContract));
            callValues[i] = 1;
            callDatas[i] = abi.encodeCall(nftContract.mint, (address(cf)));
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionBatchBuyCrowdfund.NotEnoughTokensBoughtError.selector,
                3,
                4
            )
        );
        // Buy the tokens.
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
                minTokensBought: tokenIds.length + 1,
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
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        bytes[] memory callDatas = new bytes[](3);
        bytes32[][] memory proofs = new bytes32[][](3);
        for (uint256 i; i < tokenIds.length; i++) {
            tokens[i] = nftContract;
            tokenIds[i] = i + 1;
            callTargets[i] = payable(address(nftContract));
            callValues[i] = 1;
            callDatas[i] = abi.encodeCall(nftContract.mint, (address(cf)));
        }
        vm.expectRevert(
            abi.encodeWithSelector(CollectionBatchBuyCrowdfund.NotEnoughEthUsedError.selector, 3, 4)
        );
        // Buy the tokens.
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
                minTokensBought: tokenIds.length,
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
        IERC721[] memory tokens = new IERC721[](3);
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[2] = 2;
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        bytes[] memory callDatas = new bytes[](3);
        bytes32[][] memory proofs = new bytes32[][](3);
        for (uint256 i; i < tokenIds.length; i++) {
            // Ensure one token will fail to be bought
            if (i == 1) continue;

            tokens[i] = nftContract;
            callTargets[i] = payable(address(nftContract));
            callValues[i] = 1;
            callDatas[i] = abi.encodeCall(nftContract.mint, (address(cf)));
        }
        // Check that token length is updated from 3 to 2 when creating the party
        IERC721[] memory expectedTokens = new IERC721[](2);
        uint256[] memory expectedTokenIds = new uint256[](2);
        for (uint256 i; i < expectedTokenIds.length; i++) {
            expectedTokens[i] = nftContract;
            expectedTokenIds[i] = i + 1;
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
            expectedTokens,
            expectedTokenIds
        );
        // Buy the tokens.
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
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
        // Setup parameters to batch buy.
        uint256[] memory tokenIds = new uint256[](0);
        address payable[] memory callTargets = new address payable[](0);
        uint96[] memory callValues = new uint96[](0);
        bytes[] memory callDatas = new bytes[](0);
        bytes32[][] memory proofs = new bytes32[][](0);
        // Buy the tokens.
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionBatchBuyCrowdfund.InvalidMinTokensBoughtError.selector,
                0
            )
        );
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
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
        // Setup parameters to batch buy.
        uint256[] memory tokenIds = new uint256[](0);
        address payable[] memory callTargets = new address payable[](0);
        uint96[] memory callValues = new uint96[](0);
        bytes[] memory callDatas = new bytes[](0);
        bytes32[][] memory proofs = new bytes32[][](0);
        // Buy the tokens.
        vm.expectRevert(CollectionBatchBuyCrowdfund.NothingBoughtError.selector);
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
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
        IERC721[] memory tokens = new IERC721[](3);
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        bytes[] memory callDatas = new bytes[](3);
        bytes32[][] memory proofs = new bytes32[][](3);
        for (uint256 i; i < tokenIds.length; i++) {
            tokens[i] = nftContract;
            tokenIds[i] = i + 1;
            // Mint tokens to crowdfund for free.
            nftContract.mint(address(cf));
        }
        // Buy the tokens.
        vm.expectRevert(CollectionBatchBuyCrowdfund.NothingBoughtError.selector);
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
                minTokensBought: tokenIds.length,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }

    function test_batchBuy_failedToBuy() public {
        // Create the crowdfund.
        CollectionBatchBuyCrowdfund cf = _createCrowdfund();
        // Setup parameters to batch buy.
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        bytes[] memory callDatas = new bytes[](3);
        bytes32[][] memory proofs = new bytes32[][](3);
        // Buy the tokens.
        vm.expectRevert(
            abi.encodeWithSelector(
                BuyCrowdfundBase.FailedToBuyNFTError.selector,
                address(nftContract),
                0
            )
        );
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
                minTokensBought: tokenIds.length,
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
        uint256[] memory tokenIds = new uint256[](2);
        address payable[] memory callTargets = new address payable[](2);
        uint96[] memory callValues = new uint96[](2);
        callValues[0] = 1e18;
        bytes[] memory callDatas = new bytes[](2);
        bytes32[][] memory proofs = new bytes32[][](2);
        // Buy the tokens.
        vm.expectRevert(CollectionBatchBuyCrowdfund.ContributionsSpentForFailedBuyError.selector);
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
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
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        callValues[0] = maximumPrice + 1;
        bytes[] memory callDatas = new bytes[](3);
        bytes32[][] memory proofs = new bytes32[][](3);
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
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
                minTokensBought: tokenIds.length,
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
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        bytes[] memory callDatas = new bytes[](3);
        bytes32[][] memory proofs = new bytes32[][](3);
        // Buy the tokens.
        vm.prank(_randomAddress());
        vm.expectRevert(Crowdfund.OnlyPartyHostError.selector);
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
                minTokensBought: tokenIds.length,
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
        uint256[] memory tokenIds = new uint256[](3);
        address payable[] memory callTargets = new address payable[](3);
        uint96[] memory callValues = new uint96[](3);
        bytes[] memory callDatas = new bytes[](3);
        bytes32[][] memory proofs = new bytes32[][](3);
        // Mutate governance options
        govOpts.hosts.push(_randomAddress());
        // Buy the tokens.
        vm.expectRevert(Crowdfund.InvalidGovernanceOptionsError.selector);
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
                minTokensBought: tokenIds.length,
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
        IERC721[] memory tokens = new IERC721[](1);
        uint256[] memory tokenIds = new uint256[](1);
        address payable[] memory callTargets = new address payable[](1);
        uint96[] memory callValues = new uint96[](1);
        bytes[] memory callDatas = new bytes[](1);
        bytes32[][] memory proofs = new bytes32[][](1);
        tokens[0] = nftContract;
        tokenIds[0] = tokenId;
        callTargets[0] = payable(address(nftContract));
        callValues[0] = 1;
        callDatas[0] = abi.encodeCall(nftContract.mint, (address(cf)));
        // Buy the tokens.
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
                minTokensBought: tokenIds.length,
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
        IERC721[] memory tokens = new IERC721[](1);
        uint256[] memory tokenIds = new uint256[](1);
        address payable[] memory callTargets = new address payable[](1);
        uint96[] memory callValues = new uint96[](1);
        bytes[] memory callDatas = new bytes[](1);
        bytes32[][] memory proofs = new bytes32[][](1);
        tokens[0] = nftContract;
        tokenIds[0] = tokenId;
        callTargets[0] = payable(address(nftContract));
        callValues[0] = 1;
        callDatas[0] = abi.encodeCall(nftContract.mint, (address(cf)));
        proofs[0] = new bytes32[](1);
        // Buy the tokens.
        vm.expectRevert(CollectionBatchBuyCrowdfund.InvalidTokenIdError.selector);
        cf.batchBuy(
            CollectionBatchBuyCrowdfund.BatchBuyArgs({
                tokenIds: tokenIds,
                callTargets: callTargets,
                callValues: callValues,
                callDatas: callDatas,
                proofs: proofs,
                minTokensBought: tokenIds.length,
                minTotalEthUsed: 0,
                governanceOpts: govOpts,
                hostIndex: 0
            })
        );
    }
}
