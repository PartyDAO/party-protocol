// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

struct TokenConfiguration {
    uint256 totalSupply;
    uint256 numTokensForDistribution;
    uint256 numTokensForRecipient;
    uint256 numTokensForLP;
}

interface IERC20Creator {
    function createToken(
        address partyAddress,
        string calldata name,
        string calldata symbol,
        TokenConfiguration calldata config,
        address recipientAddress
    ) external payable returns (ERC20 token);

    function feeBasisPoints() external view returns (uint16);
}
