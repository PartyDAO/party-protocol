// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

// Token and ETH distributor contract.
contract TokenDistributor is ITokenDistributor {

    struct DistributionInfo {
        uint256 distributionId;
        IERC20Token token;
        ITokenDistributorParty party;
        uint256 memberSupply;
        uint256 daoSupply;
    }

    struct DistributionState {
        // The remaining member supply.
        uint128 remainingMembersupply;
        // The 15-byte hash of the DistributionInfo.
        bytes15 distributionHash15;
        // Whether partyDao has claimed its distribution share.
        bool hasPartyDaoClaimed;
        // Whether a governance token has claimed its distribution share.
        mapping (uint256 => bool) hasTokenClaimed;
    }

    error OnlyPartyDaoError(address notDao, address partyDao);
    error InvalidDistributionInfoError(DistributionInfo info);
    error DistributionAlreadyClaimedByTokenError(uint256 distributionId, uint256 tokenId);
    error DistributionAlreadyClaimedByPartyDaoError(uint256 distributionId);

    event DistributionCreated(DistributionInfo info);
    event DistributionClaimedByPartyDao(DistributionInfo info, address recipient, uint256 amountClaimed);
    event DistributionClaimedByToken(DistributionInfo info, uint256 tokenId, address recipient, uint256 amountClaimed);

    IERC20 constant private ETH_TOKEN = IERC20(0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    IGlobals public immutable GLOBALS;

    // Last known amount of a token. Gets lazily updated
    // when creating and claiming a distribution.
    // Allows one to simply transfer and call `createDistribution()` without
    // fussing with allowances.
    mapping(IERC20 => uint256) private _storedBalances;
    // distributionId => DistributionState
    mapping(uint256 => DistributionState) private _distributionStateById;
    // Last distribution ID for a party.
    mapping(ITokenDistributorParty => uint256) public lastDistributionIdPerParty;

    modifier onlyPartyDao() {
        {
            address partyDao = IGlobals.getAddress(LibGlobals.GLOBAL_DAO_WALLET)
            if (msg.sender != partyDao) {
                revert OnlyPartyDaoError(msg.sender, partyDao);
            }
        }
        _;
    }

    constructor(IGlobals globals) {
        GLOBALS = globals;
    }

    // Create a distribution.
    // Tokens should be transferred into this contract before calling this
    // function. ETH can be attached to this call for ETH payouts.
    // The caller should implement the `ITokenDistributorParty` interface
    // (ie, be a `Party` instance).
    function createDistribution(IERC20 token)
        external
        payable
        returns (DistributionInfo memory info)
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

        ITokenDistributorParty party = ITokenDistributorParty(msg.sender);
        uint256 distId = lastDistributionIdPerParty[party]++;
        // Compute the portion of the supply reserved for the DAO
        uint256 daoSupply = supply *
            IGlobals.getUint256(LibGlobals.GLOBAL_DAO_DISTRIBUTION_SPLIT) / 1e18;
        assert(daoSupply <= supply);
        uint256 memberSupply = supply - daoSupply;
        info = new DistributionInfo({
            distributionId: distId,
            token: token,
            party: party,
            memberSupply: memberSupply,
            daoSupply: daoSupply
        });
        (
            _distributionStateById[distId].distributionHash15,
            _distributionStateById[distId].remainingMembersupply,
        ) = (_getDistributionHash(info), memberSupply);
        emit DistributionCreated(distributionInfo);
    }

    // Claim a distribution as a party member based on the weight of a
    // PartyGovernanceNFT owned by the caller.
    // The amount sent to `recipient` will be based on
    // `ITokenDistributorParty.getDistributionShareOf()`.
    function claim(
        DistributionInfo calldata info,
        uint256 tokenId,
        address payable recipient
    )
        external
        returns (uint256 amountClaimed)
    {
        DistributionState storage state = _distributionStateById[distributionId];
        if (state.distributionHash15 != _getDistributionHash(info)) {
            revert InvalidDistributionInfoError(info);
        }
        if (state.hasTokenClaimed[tokenId]) {
            revert DistributionAlreadyClaimedByTokenError(info.distributionId, tokenId);
        }
        state.hasTokenClaimed[tokenId] = true;
        // When paying out, reserve a portion based on token's distribution share.
        // This value is denominated in fractions of 1e18, where 1e18 = 100%.
        uint256 tokenSplit = party.getDistributionShareOf(governanceTokenId);
        amountClaimed = tokenSplit * info.memberSupply / 1e18;
        uint256 remainingMembersupply = state.remainingMembersupply;
        // Cap at the remaining member supply. Otherwise a malicious
        // distribution creator could drain more than the distribution supply.
        amountClaimed = amountClaimed > remainingMembersupply
            ? remainingMembersupply
            : amountClaimed;
        state.remainingMembersupply = remainingMembersupply - amountClaimed;
        _transfer(info.token, recipient, amountClaimed);
        emit DistributionClaimedByToken(info, tokenId, recipient, amountClaimed);
    }

    // Claim a distribution based on a
    function partyDaoClaim(
        DistributionInfo calldata info,
        address payable recipient
    )
        external
        onlyPartyDao
        returns (uint256 amountClaimed)
    {
        DistributionState storage state = _distributionStateById[distributionId];
        if (state.distributionHash15 != _getDistributionHash(info)) {
            revert InvalidDistributionInfoError(info);
        }
        if (state.hasPartyDaoClaimed) {
            revert DistributionAlreadyClaimedByPartyDaoError(info.distributionId);
        }
        state.hasPartyDaoClaimed = true;
        _transfer(info.token, recipient, info.daoSupply);
        emit DistributionClaimedByPartyDao(info, recipient, amountClaimed);
    }

    function _transfer(IERC20 token, address payable recipient, uint256 amount)
        private
    {
        // Reduce stored token balance.
        _storedBalances[token] -= amount;
        if (token == ETH_TOKEN) {
            recipient.call{ value: amount }("");
        } else {
            token.compatTransfer(recipient, amount);
        }
    }

    function _getDistributionHash(DistributionInfo memory info)
        private
        pure
        returns (bytes15 hash)
    {
        // TODO: consider cleaning dirty bits.
        assembly {
            hash := and(
                keccak256(info, 0xA0),
                0x0000000000000000000000000000000000ffffffffffffffffffffffffffffff
            )
        }
    }
}
