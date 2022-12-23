// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/party/PartyGovernanceNFT.sol";
import "../../contracts/globals/Globals.sol";
import "../DummyERC20.sol";
import "../DummyERC1155.sol";
import "../DummyERC721.sol";
import "../TestUtils.sol";

contract TestablePartyGovernanceNFT is PartyGovernanceNFT {
    constructor() PartyGovernanceNFT(new Globals(msg.sender)) {}

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 customizationPresetId,
        PartyGovernance.GovernanceOpts memory governanceOpts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds,
        address mintAuthority_
    ) external {
        _initialize(
            name_,
            symbol_,
            customizationPresetId,
            governanceOpts,
            preciousTokens,
            preciousTokenIds,
            mintAuthority_
        );
    }

    function getCurrentVotingPower(address voter) external view returns (uint96 vp) {
        return this.getVotingPowerAt(voter, uint40(block.timestamp));
    }

    modifier onlyDelegateCall() override {
        _;
    }
}

contract PartyGovernanceNFTUnitTest is TestUtils {
    TestablePartyGovernanceNFT nft = new TestablePartyGovernanceNFT();
    PartyGovernance.GovernanceOpts defaultGovernanceOpts;

    function _initGovernance() private {
        defaultGovernanceOpts.totalVotingPower = 1e18;
        nft.initialize(
            "TEST",
            "TST",
            0,
            defaultGovernanceOpts,
            new IERC721[](0),
            new uint256[](0),
            address(this)
        );
    }

    function test_transferFromAdjustsVotingPower() external {
        _initGovernance();
        address from = _randomAddress();
        address to = _randomAddress();
        uint256 vp = _randomUint256() % defaultGovernanceOpts.totalVotingPower;
        uint256 tokenId = nft.mint(from, vp, from);
        vm.prank(from);
        nft.transferFrom(from, to, tokenId);
        assertEq(nft.getCurrentVotingPower(from), 0);
        assertEq(nft.getCurrentVotingPower(to), vp);
    }

    function test_safeTransferFromAdjustsVotingPower() external {
        _initGovernance();
        address from = _randomAddress();
        address to = _randomAddress();
        uint256 vp = _randomUint256() % defaultGovernanceOpts.totalVotingPower;
        uint256 tokenId = nft.mint(from, vp, from);
        vm.prank(from);
        nft.safeTransferFrom(from, to, tokenId);
        assertEq(nft.getCurrentVotingPower(from), 0);
        assertEq(nft.getCurrentVotingPower(to), vp);
    }

    function test_safeTransferFrom2AdjustsVotingPower() external {
        _initGovernance();
        address from = _randomAddress();
        address to = _randomAddress();
        uint256 vp = _randomUint256() % defaultGovernanceOpts.totalVotingPower;
        uint256 tokenId = nft.mint(from, vp, from);
        vm.prank(from);
        nft.safeTransferFrom(from, to, tokenId, "");
        assertEq(nft.getCurrentVotingPower(from), 0);
        assertEq(nft.getCurrentVotingPower(to), vp);
    }

    function test_transferMergesVotingPower() external {
        _initGovernance();
        address from1 = _randomAddress();
        uint256 vp1 = _randomUint256() % defaultGovernanceOpts.totalVotingPower;
        uint256 tokenId1 = nft.mint(from1, vp1, from1);
        address from2 = _randomAddress();
        uint256 vp2 = defaultGovernanceOpts.totalVotingPower - vp1;
        uint256 tokenId2 = nft.mint(from2, vp2, from2);

        address to = _randomAddress();
        vm.prank(from1);
        nft.transferFrom(from1, to, tokenId1);
        assertEq(nft.getCurrentVotingPower(to), vp1);
        vm.prank(from2);
        nft.transferFrom(from2, to, tokenId2);
        assertEq(nft.getCurrentVotingPower(to), vp1 + vp2);
    }

    function test_canMintMultipleTokensToOneOwner() external {
        _initGovernance();
        address from = _randomAddress();
        uint256 vp1 = (_randomUint256() % defaultGovernanceOpts.totalVotingPower) / 10;
        uint256 vp2 = vp1 + 1;
        nft.mint(from, vp1, from);
        nft.mint(from, vp2, from);
        assertEq(nft.getCurrentVotingPower(from), vp1 + vp2);
    }

    function test_canTransferMultipleTokens() external {
        _initGovernance();
        address from = _randomAddress();
        uint256 vp1 = _randomUint256() % defaultGovernanceOpts.totalVotingPower;
        uint256 vp2 = defaultGovernanceOpts.totalVotingPower - vp1;
        uint256 tokenId1 = nft.mint(from, vp1, from);
        uint256 tokenId2 = nft.mint(from, vp2, from);

        address to = _randomAddress();
        vm.prank(from);
        nft.transferFrom(from, to, tokenId1);
        assertEq(nft.getCurrentVotingPower(to), vp1);
        vm.prank(from);
        nft.transferFrom(from, to, tokenId2);
        assertEq(nft.getCurrentVotingPower(to), vp1 + vp2);
    }

    function test_onlyAuthorityCanMint() external {
        _initGovernance();
        address from = _randomAddress();
        uint256 vp = _randomUint256() % defaultGovernanceOpts.totalVotingPower;
        address notAuthority = _randomAddress();
        vm.prank(notAuthority);
        vm.expectRevert(
            abi.encodeWithSelector(
                PartyGovernanceNFT.OnlyMintAuthorityError.selector,
                notAuthority,
                address(this)
            )
        );
        nft.mint(from, vp, from);
    }

    function test_cannotMintBeyondTotalVotingPower() external {
        _initGovernance();
        address voter = _randomAddress();
        uint256 vp = defaultGovernanceOpts.totalVotingPower + 1;
        nft.mint(voter, vp, voter);
        assertEq(nft.getCurrentVotingPower(voter), defaultGovernanceOpts.totalVotingPower);
        assertEq(nft.mintedVotingPower(), defaultGovernanceOpts.totalVotingPower);
    }

    function test_cannotMintBeyondTotalVotingPower_inTwoMints() external {
        _initGovernance();
        address voter = _randomAddress();
        uint256 vp = defaultGovernanceOpts.totalVotingPower - 1;
        nft.mint(voter, vp, voter);
        assertEq(nft.mintedVotingPower(), vp);
        assertEq(nft.getCurrentVotingPower(voter), vp);
        voter = _randomAddress();
        nft.mint(voter, 2, voter);
        assertEq(nft.mintedVotingPower(), defaultGovernanceOpts.totalVotingPower);
        assertEq(nft.getCurrentVotingPower(voter), 1);
    }
}
