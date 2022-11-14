// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "contracts/proposals/ListOnZoraProposal.sol";
import "contracts/globals/Globals.sol";
import "../TestUtils.sol";
import "./MockZoraAuctionHouse.sol";
import "./TestableListOnZoraProposal.sol";
import "../DummyERC721.sol";

contract ListOnZoraProposalUnitTest is Test, TestUtils {
    MockZoraAuctionHouse zora = new MockZoraAuctionHouse();
    Globals globals = new Globals(address(this));
    TestableListOnZoraProposal impl =
        new TestableListOnZoraProposal(IGlobals(address(globals)), IZoraAuctionHouse(zora));
    DummyERC721 token = new DummyERC721();
    uint256 tokenId = token.mint(address(impl));

    event ZoraAuctionCreated(
        uint256 auctionId,
        IERC721 token,
        uint256 tokenId,
        uint256 startingPrice,
        uint40 duration,
        uint40 timeoutTime
    );

    constructor() {
        globals.setUint256(LibGlobals.GLOBAL_ZORA_MIN_AUCTION_DURATION, 1 days);
        globals.setUint256(LibGlobals.GLOBAL_ZORA_MAX_AUCTION_DURATION, 3 days);
        globals.setUint256(LibGlobals.GLOBAL_ZORA_MAX_AUCTION_TIMEOUT, 7 days);
    }

    function _createTestProposal(
        uint256 listPrice,
        uint40 timeout,
        uint40 duration,
        ListOnZoraProposal.ZoraStep step
    )
        private
        view
        returns (
            ListOnZoraProposal.ZoraProposalData memory data,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        )
    {
        data = ListOnZoraProposal.ZoraProposalData({
            listPrice: listPrice,
            timeout: timeout,
            duration: duration,
            token: token,
            tokenId: tokenId
        });

        params = IProposalExecutionEngine.ExecuteProposalParams({
            proposalId: _randomUint256(),
            proposalData: abi.encode(data),
            progressData: abi.encode(step),
            extraData: "",
            flags: 0,
            preciousTokens: new IERC721[](0),
            preciousTokenIds: new uint256[](0)
        });
    }

    function _createTestProposal()
        private
        view
        returns (
            ListOnZoraProposal.ZoraProposalData memory data,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        )
    {
        return _createTestProposal(1 ether, 1 days, 1 days, ListOnZoraProposal.ZoraStep.None);
    }

    function test_executeListOnZora_durationBounds() external {
        (
            ListOnZoraProposal.ZoraProposalData memory data,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        ) = _createTestProposal();

        // Test minimum auction duration is enforced
        uint40 minDuration = uint40(
            globals.getUint256(LibGlobals.GLOBAL_ZORA_MIN_AUCTION_DURATION)
        );
        data.duration = minDuration / 2;
        params.proposalData = abi.encode(data);
        _expectEmit0();
        emit ZoraAuctionCreated(
            zora.lastAuctionId() + 1,
            data.token,
            data.tokenId,
            data.listPrice,
            minDuration,
            uint40(block.timestamp + data.timeout)
        );
        impl.executeListOnZora(params);

        // Test maximum auction duration is enforced
        uint40 maxDuration = uint40(
            globals.getUint256(LibGlobals.GLOBAL_ZORA_MAX_AUCTION_DURATION)
        );
        data.duration = maxDuration * 2;
        params.proposalData = abi.encode(data);
        _expectEmit0();
        emit ZoraAuctionCreated(
            zora.lastAuctionId() + 1,
            data.token,
            data.tokenId,
            data.listPrice,
            maxDuration,
            uint40(block.timestamp + data.timeout)
        );
        impl.executeListOnZora(params);
    }

    function test_executeListOnZora_timeoutBounds() external {
        (
            ListOnZoraProposal.ZoraProposalData memory data,
            IProposalExecutionEngine.ExecuteProposalParams memory params
        ) = _createTestProposal();

        // Test maximum auction timeout is enforced
        uint40 maxTimeout = uint40(globals.getUint256(LibGlobals.GLOBAL_ZORA_MAX_AUCTION_TIMEOUT));
        data.timeout = maxTimeout * 2;
        params.proposalData = abi.encode(data);
        _expectEmit0();
        emit ZoraAuctionCreated(
            zora.lastAuctionId() + 1,
            data.token,
            data.tokenId,
            data.listPrice,
            data.duration,
            uint40(block.timestamp + maxTimeout)
        );
        impl.executeListOnZora(params);
    }
}
