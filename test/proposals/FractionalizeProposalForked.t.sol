// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../../contracts/proposals/FractionalizeProposal.sol";

import "../TestUtils.sol";
import "../DummyERC721.sol";

contract TestableFractionalizeProposal is FractionalizeProposal {
    event MockCreateDistribution(
        address caller,
        ITokenDistributor.TokenType tokenType,
        address token,
        uint256 tokenId
    );

    PartyGovernance.GovernanceValues _governanceValues;
    string public constant name = "Test party";
    string public constant symbol = "TST";

    constructor(IFractionalV1VaultFactory vaultFactory) FractionalizeProposal(vaultFactory) {}

    function getGovernanceValues() external view returns (PartyGovernance.GovernanceValues memory) {
        return _governanceValues;
    }

    function executeFractionalize(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    ) external returns (bytes memory nextProgressData) {
        return _executeFractionalize(params);
    }

    function setTotalVotingPower(uint96 totalVotingPower) external {
        _governanceValues.totalVotingPower = totalVotingPower;
    }

    // This is here because during the proposal, the party will call
    // `distribute()` on itself.
    function distribute(
        uint256,
        ITokenDistributor.TokenType tokenType,
        address token,
        uint256 tokenId
    ) external returns (ITokenDistributor.DistributionInfo memory distInfo) {
        if (msg.sender != address(this)) {
            revert("FAIL");
        }

        emit MockCreateDistribution(msg.sender, tokenType, token, tokenId);

        return distInfo;
    }
}

contract EmptyContract {}

contract FractionalizeProposalForkedTest is TestUtils {
    using LibRawResult for bytes;

    event MockCreateDistribution(
        address caller,
        ITokenDistributor.TokenType tokenType,
        address token,
        uint256 tokenId
    );

    event FractionalV1VaultCreated(
        IERC721 indexed token,
        uint256 indexed tokenId,
        uint256 vaultId,
        IERC20 vault
    );

    IFractionalV1VaultFactory VAULT_FACTORY =
        IFractionalV1VaultFactory(0x85Aa7f78BdB2DE8F3e0c0010d99AD5853fFcfC63);
    TestableFractionalizeProposal impl = new TestableFractionalizeProposal(VAULT_FACTORY);
    DummyERC721 erc721 = new DummyERC721();

    constructor() {
        impl.setTotalVotingPower(uint96(_randomUint256()));
    }

    function testForked_canFractionalize() external onlyForked {
        uint256 tokenId = erc721.mint(address(impl));
        uint256 expectedVaultId = VAULT_FACTORY.vaultCount();
        IFractionalV1Vault expectedVault = _getNextVault();
        _expectEmit2();
        emit FractionalV1VaultCreated(erc721, tokenId, expectedVaultId, expectedVault);
        _expectEmit0();
        emit MockCreateDistribution(
            address(impl),
            ITokenDistributor.TokenType.Erc20,
            address(expectedVault),
            expectedVaultId
        );
        bytes memory nextProgressData = impl.executeFractionalize(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: "",
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(
                    FractionalizeProposal.FractionalizeProposalData({
                        token: erc721,
                        tokenId: tokenId
                    })
                )
            })
        );
        assertEq(nextProgressData.length, 0);
        assertEq(
            expectedVault.balanceOf(address(impl)),
            impl.getGovernanceValues().totalVotingPower
        );
        assertEq(expectedVault.curator(), address(1));
    }

    function testForked_canBuyout() external onlyForked {
        uint256 tokenId = erc721.mint(address(impl));
        uint256 listPrice = 1337 ether;
        IFractionalV1Vault vault = _getNextVault();
        impl.executeFractionalize(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: "",
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(
                    FractionalizeProposal.FractionalizeProposalData({
                        token: erc721,
                        tokenId: tokenId
                    })
                )
            })
        );

        // Set desired buyout price
        vm.prank(address(impl));
        vault.updateUserPrice(listPrice);

        address payable bidder1 = _randomAddress();
        address payable bidder2 = _randomAddress();

        // Start the auction
        vm.prank(bidder1);
        vm.deal(bidder1, listPrice);
        vault.start{ value: listPrice }();

        assertEq(vault.livePrice(), listPrice);
        assertEq(vault.winning(), bidder1);

        // Bid on the auction
        uint256 bidAmount = listPrice * 2;
        vm.prank(bidder2);
        vm.deal(bidder2, bidAmount);
        vault.bid{ value: bidAmount }();

        assertEq(vault.livePrice(), bidAmount);
        assertEq(vault.winning(), bidder2);

        // End the auction
        vm.warp(vault.auctionEnd());
        vault.end();

        assertEq(erc721.ownerOf(tokenId), bidder2);
    }

    function testForked_canRedeem() public onlyForked {
        uint256 tokenId = erc721.mint(address(impl));
        IFractionalV1Vault vault = _getNextVault();
        impl.executeFractionalize(
            IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: "",
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(
                    FractionalizeProposal.FractionalizeProposalData({
                        token: erc721,
                        tokenId: tokenId
                    })
                )
            })
        );

        address redeemer = _randomAddress();

        // Transfer all ERC20 fractions to redeemer to redeem for ERC721
        uint256 totalBalance = impl.getGovernanceValues().totalVotingPower;
        vm.prank(address(impl));
        vault.transfer(redeemer, totalBalance);

        // Redeem for ERC721
        vm.prank(redeemer);
        vault.redeem();

        assertEq(erc721.ownerOf(tokenId), redeemer);
    }

    function _getNextVault() private returns (IFractionalV1Vault v) {
        try this.__getNextVaultAndRevert() {
            assert(false);
        } catch (bytes memory revertData) {
            v = abi.decode(revertData, (IFractionalV1Vault));
        }
    }

    function __getNextVaultAndRevert() external {
        // Deploy a random contract as the vault factory to get its next deployment
        // address.
        vm.prank(address(VAULT_FACTORY));
        bytes memory revertData = abi.encode(address(new EmptyContract()));
        revertData.rawRevert();
    }
}
