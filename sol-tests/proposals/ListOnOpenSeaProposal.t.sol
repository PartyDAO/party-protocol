// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/globals/Globals.sol";
import "../../contracts/globals/LibGlobals.sol";

import "../TestUtils.sol";
import "../DummyERC721.sol";
import "./TestableListOnOpenSeaProposal.sol";

contract ListOnOpenSeaProposalTest is Test, TestUtils {
    uint256 constant ZORA_LISTING_DURATION = 60 * 60 * 24;
    TestableListOnOpenSeaProposal impl;
    Globals globals;
    SharedWyvernV2Maker maker;
    IZoraAuctionHouse ZORA =
        IZoraAuctionHouse(0xE468cE99444174Bd3bBBEd09209577d25D1ad673);
    DummyERC721 preciousToken;
    uint256 preciousTokenId;

    function setUp() public onlyForked {
        globals = new Globals(address(this));
        globals.setUint256(
            LibGlobals.GLOBAL_OS_ZORA_AUCTION_DURATION,
            ZORA_LISTING_DURATION
        );
        preciousToken = new DummyERC721();
        preciousTokenId = preciousToken.mint(address(this));
        impl = new TestableListOnOpenSeaProposal(
            globals,
            maker,
            ZORA
        );
        preciousToken.transferFrom(address(this), address(impl), preciousTokenId);
    }

    function testForkedExecution() public onlyForked {
        ListOnOpenSeaProposal.OpenSeaProposalData memory proposalData =
            ListOnOpenSeaProposal.OpenSeaProposalData({
                listPrice: 1e18,
                durationInSeconds: uint40(ZORA_LISTING_DURATION * 7)
            });
        IProposalExecutionEngine.ExecuteProposalParams memory executeParams =
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomBytes32(),
                proposalData: abi.encode(proposalData),
                progressData: "",
                flags: 0,
                preciousToken: preciousToken,
                preciousTokenId: preciousTokenId
            });
        // This will list on zora.
        bytes memory rawProgressData = impl.executeListOnOpenSea(executeParams);
        assertTrue(rawProgressData.length != 0);
        {
            (
                ListOnOpenSeaProposal.OpenSeaStep step,
                ListOnZoraProposal.ZoraProgressData memory progressData
            ) = abi.decode(rawProgressData, (
                ListOnOpenSeaProposal.OpenSeaStep,
                ListOnZoraProposal.ZoraProgressData
            ));
            assertTrue(step == ListOnOpenSeaProposal.OpenSeaStep.ListedOnZora);
            assertTrue(progressData.auctionId != 0);
            assertTrue(progressData.minExpiry == block.timestamp + ZORA_LISTING_DURATION);
        }
        // TODO: other steps...
    }
}
