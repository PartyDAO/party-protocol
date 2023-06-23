// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import "../../contracts/utils/LibSafeERC721.sol";
import "../DummyERC721.sol";
import "../TestUtils.sol";

contract EmptyContract {}

contract BadERC721 {
    function ownerOf(uint256) external pure returns (address) {}
}

contract LibSafeERC721Test is TestUtils {
    using LibSafeERC721 for IERC721;

    IERC721 token = new DummyERC721();
    IERC721 eoa = IERC721(vm.addr(1));
    IERC721 emptyContract = IERC721(address(new EmptyContract()));
    IERC721 badERC721 = IERC721(address(new BadERC721()));
    uint256 tokenId = DummyERC721(address(token)).mint(address(this));

    function test_safeOwnerOf_works() external {
        assertEq(token.safeOwnerOf(tokenId), address(this));
    }

    function test_safeOwnerOf_doesntRevertIfTokenIDDoesntExist() external {
        assertEq(token.safeOwnerOf(999), address(0));
    }

    function test_safeOwnerOf_doesntRevertOnEOA() external {
        assertEq(eoa.safeOwnerOf(tokenId), address(0));
    }

    function test_safeOwnerOf_doesntRevertOnEmptyContract() external {
        assertEq(emptyContract.safeOwnerOf(tokenId), address(0));
    }

    function test_safeOwnerOf_doesntRevertOnBadERC721() external {
        assertEq(badERC721.safeOwnerOf(tokenId), address(0));
    }
}
