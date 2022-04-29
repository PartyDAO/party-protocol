// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Token and ETH distributor contract.
contract TokenDistributor is ITokenDistributor {
    IERC20 constant private ETH_TOKEN = IERC20(0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    IGlobals public immutable GLOBALS;
    uint256 public immutable PARTY_DAO_SPLIT;
    address payable public immutable PARTY_DAO;

    // Last known amount of a token. Gets lazily updated
    // when creating and claiming a distribution.
    // Allows one to simply transfer and call `createDistribution()` without
    // fussing with allowances.
    mapping(IERC20 => uint256) private _storedBalances;
    // Last seen balances of an ERC20 token. (and ETH)
    mapping(uint256 => bytes32) publthe ic distributionHashById;
    // distributionId => tokenId => hasTokenClaimed
    mapping(uint256 => mapping(uint256 => boolean)) private _hasTokenClaimed;
    // distributionId => hasPartyDaoClaimed
    mapping(uint256 => boolean) private _hasPartyDaoClaimed;
    // ID of the next distribution returned by `createDistribution()`.
    uint256 public nextDistributionId = 1;

    modifier onlyPartyDao() {
        require(msg.sender == PARTY_DAO, 'NOT_ALLOWED');
        _;
    }

    constructor(IGlobals globals, address payable partyDao, uint256 partyDaoSplit) {
        GLOBALS = globals;
        PARTY_DAO_SPLIT = partyDaoSplit;
        PARTY_DAO = partyDao;
    }

    function getDistributionHash(
        ITokenDistributorParty party,
        IERC20 token,
        uint256 supply
    )
        public
        view
        returns (bytes32 hash)
    {
        // TODO: But in assembly.
        return keccak256(abi.encode(party, token, supply));
    }

    // Create a distribution.
    // Tokens should be transferred into this contract before calling this
    // function. ETH can be attached to this call for ETH payouts.
    // The caller should implement the `ITokenDistributorParty` interface
    // (ie, be a `Party` instance).
    function createDistribution(IERC20 token)
        external
        payable
        returns (uint256 distributionId)
    {
        uint256 bal;
        if (token == ETH_TOKEN) {
            bal = address(this).balance;
        } else {
            bal = token.balanceOf(address(this));
        }
        // Used the delta between actual balance _storedBalances as the
        // distribution supply.
        uint256 supply = bal - _storedBalances[token];
        _storedBalances[token] = bal;

        uint256 distId = nextDistributionId++;
        ITokenDistributorParty party = ITokenDistributorParty(msg.sender);
        distributionHashById[distId] = getDistributionHash(
            party,
            token,
            supply,
        );
        emit DistributionCreated(distId, party, token, supply);
    }

    // Claim a distribution as a party member based on the weight of a
    // PartyGovernanceNFT owned by the caller.
    // The amount sent to `recipient` will be based on
    // `ITokenDistributorParty.getDistributionShareOf()`.
    function claim(
        uint256 distributionId,
        ITokenDistributorParty party,
        IERC20 token,
        uint256 supply,
        uint256 governanceTokenId,
        address payable recipient
    )
        external
        returns (uint256 amountClaimed)
    {
        bytes32 distHash = distributionHashById[distributionId];
        require(
            getDistributionHash(party, token, supply) == distHash,
            'INVALID_DISTRIBUTION_DATA'
        );
        require(!_hasTokenClaimed[distributionId][tokenId], 'ALREADY_CLAIMED');
        _hasTokenClaimed[distributionId][tokenId] = true;
        // When paying out, reserve a portion based on partydao split.
        // This value is denominated in fractions of 1e18, where 1e18 = 100%.
        uint256 tokenSplit = party.getDistributionShareOf(governanceTokenId);
        uint256 amount = ...
        // ...
        _transfer(token, recipient, amount);
    }

    // Claim a distribution based on a
    function partyDaoClaim(
        uint256 distributionId,
        ITokenDistributorParty party,
        IERC20 token,
        uint256 supply,
        address recipient
    )
        external
        onlyPartyDao
        returns (uint256 amountClaimed)
    {
        bytes32 distHash = distributionHashById[distributionId];
        require(
            getDistributionHash(party, token, supply) == distHash,
            'INVALID_DISTRIBUTION_DATA'
        );
        require(!_hasPartyDaoClaimed[distributionId], 'ALREADY_CLAIMED');
        _hasPartyDaoClaimed[distributionId] = true;
        uint256 amount = PARTY_DAO_SPLIT * supply / 1e18;
        _transfer(token, recipient, amount);
    }

    function _transfer(IERC20 token, address payable recipient, uint256 amount)
        private
    {
        // Reduce stored token balance.
        _storedBalances[token] -= amount;
        if (token == ETH_TOKEN) {
            recipient.call{ gas: gasleft(), value: amount }("");
        } else {
            token.compatTransfer(recipient, amount);
        }
    }
}
