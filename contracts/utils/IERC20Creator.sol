// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

struct TokenConfiguration {
    uint256 totalSupply;
    uint256 numTokensForDistribution;
    uint256 numTokensForRecipient;
    uint256 numTokensForLP;
}

struct TokenDistributionConfiguration {
    uint256 totalSupply;
    uint256 numTokensForDistribution;
    uint256 numTokensForRecipient;
    uint256 numTokensForLP;
}

struct FeeRecipient {
    address recipient;
    uint16 percentageBps;
}

struct PositionParams {
    address party;
    bool isFirstRecipientDistributor;
    FeeRecipient[] recipients;
}

interface IERC20Creator {
    function createToken(
        address partyAddress,
        string calldata name,
        string calldata symbol,
        TokenConfiguration calldata config,
        address recipientAddress
    ) external payable returns (ERC20 token);
}

interface IERC20CreatorV3 {
    function createToken(
        address party,
        string memory name,
        string memory symbol,
        TokenDistributionConfiguration memory config,
        address tokenRecipientAddress,
        address feeCollectorAddress,
        uint16 poolFee,
        PositionParams calldata positionParams
    ) external payable returns (ERC20 token);
}
