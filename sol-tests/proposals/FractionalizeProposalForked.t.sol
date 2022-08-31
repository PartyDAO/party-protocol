// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "../../contracts/proposals/FractionalizeProposal.sol";

import "../TestUtils.sol";
import "../DummyERC721.sol";

contract TestableFractionalizeProposal is FractionalizeProposal {
    PartyGovernance.GovernanceValues _governanceValues;
    string public constant name = 'Test party';
    string public constant symbol = 'TST';

    constructor(IFractionalV1VaultFactory vaultFactory)
        FractionalizeProposal(vaultFactory)
    {}

    function getGovernanceValues() external view returns (PartyGovernance.GovernanceValues memory) {
        return _governanceValues;
    }

    function executeFractionalize(
        IProposalExecutionEngine.ExecuteProposalParams memory params
    )
        external
        returns (bytes memory nextProgressData)
    {
        return _executeFractionalize(params);
    }

    function setTotalVotingPower(uint96 totalVotingPower) external {
        _governanceValues.totalVotingPower = totalVotingPower;
    }
}

contract EmptyContract {}

contract FractionalizeProposalForkedTest is TestUtils {
    using LibRawResult for bytes;

    event FractionalV1VaultCreated(
        IERC721 indexed token,
        uint256 indexed tokenId,
        uint256 vaultId,
        IERC20 vault,
        uint256 listPrice
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
        uint256 listPrice = 1337 ether;
        uint256 expectedVaultId = VAULT_FACTORY.vaultCount();
        IFractionalV1Vault expectedVault = _getNextVault();
        _expectEmit2();
        emit FractionalV1VaultCreated(erc721, tokenId, expectedVaultId, expectedVault, listPrice);
        bytes memory nextProgressData =
            impl.executeFractionalize(IProposalExecutionEngine.ExecuteProposalParams({
                proposalId: _randomUint256(),
                progressData: "",
                extraData: "",
                flags: 0,
                preciousTokens: new IERC721[](0),
                preciousTokenIds: new uint256[](0),
                proposalData: abi.encode(FractionalizeProposal.FractionalizeProposalData({
                    token: erc721,
                    tokenId: tokenId,
                    listPrice: listPrice
                }))
            }));
        assertEq(nextProgressData.length, 0);
        assertEq(expectedVault.balanceOf(address(impl)), impl.getGovernanceValues().totalVotingPower);
        assertEq(expectedVault.reservePrice(), listPrice);
        assertEq(expectedVault.curator(), address(0));
    }

    function _getNextVault()
        private
        returns (IFractionalV1Vault v)
    {
        try this.__getNextVaultAndRevert() { assert(false); }
        catch (bytes memory revertData) { v = abi.decode(revertData, (IFractionalV1Vault)); }
    }

    function __getNextVaultAndRevert() external {
        // Deploy a random contract as the vault factory to get its next deployment
        // address.
        vm.prank(address(VAULT_FACTORY));
        bytes memory revertData = abi.encode(address(new EmptyContract()));
        revertData.rawRevert();
    }
}
