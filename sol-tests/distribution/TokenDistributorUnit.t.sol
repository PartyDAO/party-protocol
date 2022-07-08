// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "forge-std/Test.sol";

import "../../contracts/distribution/TokenDistributor.sol";
import "../../contracts/distribution/ITokenDistributorParty.sol";
import "../../contracts/globals/Globals.sol";

import "../TestUtils.sol";
import "../DummyERC20.sol";
import "../DummyERC1155.sol";

contract TestParty is ITokenDistributorParty {
    mapping (uint256 => address payable) _owners;
    mapping (uint256 => uint256) _shares;

    function mintShare(address payable owner, uint256 tokenId, uint256 share)
        external
        returns (address payable owner_, uint256 tokenId_, uint256 share_)
    {
        _owners[tokenId] = owner;
        _shares[tokenId] = share;
        return (owner, tokenId, share);
    }

    function ownerOf(uint256 tokenId)
        external
        view
        returns (address)
    {
        return _owners[tokenId];
    }

    function getDistributionShareOf(uint256 tokenId)
        external
        view
        returns (uint256)
    {
        return _shares[tokenId];
    }
}

contract TokenDistributorUnitTest is Test, TestUtils {

    Globals globals;
    TokenDistributor distributor;
    TestParty party;
    address payable constant DEFAULT_FEE_RECIPIENT = payable(0xfeefeefeefeefeefeefeefeefeefeefeefeefeef);
    uint16 constant DEFAULT_FEE_BPS = 0.02e4;

    constructor() {
        globals = new Globals(address(this));
        distributor = new TokenDistributor(globals);
        party = new TestParty();
    }

    function _createShare(address)

    function test_NativeToken_oneMemberNoFees() external {
        (address member, uint256 tokenId,) =
            party.mintShare(_randomAddress(), _randomUint256(), 100e18);
        (ITokenDistributor.DistributionInfo memory di) =
            distributor.createNativeDistribution(DEFAULT_FEE_RECIPIENT, DEFAULT_FEE_BPS);
        vm.prank(member);
        distributor.claim(di, tokenId);
    }
}
