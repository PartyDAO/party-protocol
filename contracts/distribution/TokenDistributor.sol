// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC20.sol";
import "../utils/LibAddress.sol";
import "../utils/LibERC20Compat.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibSafeCast.sol";

import "./ITokenDistributorParty.sol";

// Token and ETH distributor contract.
contract TokenDistributor {
    using LibAddress for address payable;
    using LibERC20Compat for IERC20;
    using LibRawResult for bytes;
    using LibSafeCast for uint256;

    struct DistributionInfo {
        uint256 distributionId;
        IERC20 token;
        ITokenDistributorParty party;
        uint256 memberSupply;
        uint256 daoSupply;
    }

    struct DistributionState {
        // The remaining member supply.
        uint128 remainingMemberSupply;
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
    error Uint256ToUint128CastOutOfRangeError(uint256 value);
    error MustOwnTokenError(address sender, address expectedOwner, uint256 tokenId);
    error EmergencyActionsNotAllowed();
    error InvalidDistributionSupply(uint256 supplyAmount, uint256 daoSupply);

    event DistributionCreated(DistributionInfo info);
    event DistributionClaimedByPartyDao(DistributionInfo info, address recipient, uint256 amountClaimed);
    event DistributionClaimedByToken(DistributionInfo info, uint256 tokenId, address recipient, uint256 amountClaimed);

    IERC20 constant private ETH_TOKEN = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    IGlobals public immutable GLOBALS;

    bool public allowEmergencyActions = true;

    // Last distribution ID for a party.
    mapping(ITokenDistributorParty => uint256) public lastDistributionIdPerParty;
    // Last known amount of a token. Gets lazily updated
    // when creating and claiming a distribution.
    // Allows one to simply transfer and call `createDistribution()` without
    // fussing with allowances.
    mapping(IERC20 => uint256) private _storedBalances;
    // tokenDistributorParty => distributionId => DistributionState
    mapping(ITokenDistributorParty => mapping(uint256 => DistributionState)) private _distributionStates;

    modifier onlyPartyDao() {
        {
            address partyDao = GLOBALS.getAddress(LibGlobals.GLOBAL_DAO_WALLET);
            if (msg.sender != partyDao) {
                revert OnlyPartyDaoError(msg.sender, partyDao);
            }
        }
        _;
    }

    modifier onlyIfEmergencyActionsAllowed() {
        if (!allowEmergencyActions) {
            revert EmergencyActionsNotAllowed();
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

        if (supply == 0) {
            revert InvalidDistributionSupply(0, 0);
        }

        _storedBalances[token] = bal;

        ITokenDistributorParty party = ITokenDistributorParty(msg.sender);
        uint256 distId = ++lastDistributionIdPerParty[party];
        // Compute the portion of the supply reserved for the DAO
        uint256 daoSplitPercent = GLOBALS.getUint256(LibGlobals.GLOBAL_DAO_DISTRIBUTION_SPLIT);
        uint256 daoSupply = supply * daoSplitPercent / 1e18;
        if (daoSupply > supply) {
            revert InvalidDistributionSupply(supply, daoSupply);
        }
        

        uint256 memberSupply = supply - daoSupply;
        info = DistributionInfo({
            distributionId: distId,
            token: token,
            party: party,
            memberSupply: memberSupply,
            daoSupply: daoSupply
        });
        (
            _distributionStates[party][distId].distributionHash15,
            _distributionStates[party][distId].remainingMemberSupply
        ) = (_getDistributionHash(info), memberSupply.safeCastUint256ToUint128());
        emit DistributionCreated(info);
    }

    // Claim a distribution as a party member based on the weight of a
    // PartyGovernanceNFT owned by the caller.
    // The amount sent will be based on
    // `ITokenDistributorParty.getDistributionShareOf()`.
    function claim(
        DistributionInfo calldata info,
        uint256 tokenId
    )
        external
        returns (uint256 amountClaimed)
    {
        address ownerOfToken = info.party.ownerOf(tokenId);
        if (msg.sender != ownerOfToken) {
            revert MustOwnTokenError(msg.sender, ownerOfToken, tokenId);
        }
        DistributionState storage state = _distributionStates[info.party][info.distributionId];
        if (state.distributionHash15 != _getDistributionHash(info)) {
            revert InvalidDistributionInfoError(info);
        }
        if (state.hasTokenClaimed[tokenId]) {
            revert DistributionAlreadyClaimedByTokenError(info.distributionId, tokenId);
        }
        state.hasTokenClaimed[tokenId] = true;

        amountClaimed = getClaimAmount(info, tokenId);

        uint128 remainingMemberSupply = state.remainingMemberSupply;
        // Cap at the remaining member supply. Otherwise a malicious
        // distribution creator could drain more than the distribution supply.
        amountClaimed = amountClaimed > remainingMemberSupply
            ? remainingMemberSupply
            : amountClaimed;

        state.remainingMemberSupply =
            remainingMemberSupply - amountClaimed.safeCastUint256ToUint128();
        _transfer(info.token, payable(ownerOfToken), amountClaimed);
        emit DistributionClaimedByToken(info, tokenId, ownerOfToken, amountClaimed);
    }

    function getClaimAmount(
        DistributionInfo calldata info,
        uint256 tokenId
    ) public view returns (uint256) {
        // When paying out, reserve a portion based on token's distribution share.
        // This value is denominated in fractions of 1e18, where 1e18 = 100%.
        uint256 tokenSplit = info.party.getDistributionShareOf(tokenId);
        return tokenSplit * info.memberSupply / 1e18;
    }

    // Claim a distribution based on a
    function partyDaoClaim(
        DistributionInfo calldata info,
        address payable recipient
    )
        external
        onlyPartyDao
    {
        DistributionState storage state = _distributionStates[info.party][info.distributionId];
        if (state.distributionHash15 != _getDistributionHash(info)) {
            revert InvalidDistributionInfoError(info);
        }
        if (state.hasPartyDaoClaimed) {
            revert DistributionAlreadyClaimedByPartyDaoError(info.distributionId);
        }
        state.hasPartyDaoClaimed = true;
        uint256 amountClaimed = info.daoSupply;
        _transfer(info.token, recipient, amountClaimed);
        emit DistributionClaimedByPartyDao(info, recipient, amountClaimed);
    }

    function hasPartyDaoClaimed(ITokenDistributorParty party, uint256 distributionId) external view returns (bool) {
        return _distributionStates[party][distributionId].hasPartyDaoClaimed;
    }

    function hasTokenIdClaimed(ITokenDistributorParty party, uint256 tokenId, uint256 distributionId) external view returns (bool) {
        return _distributionStates[party][distributionId].hasTokenClaimed[tokenId];
    }


    function getRemainingMemberSupply(ITokenDistributorParty party, uint256 distributionId) public view returns (uint256) {
        return _distributionStates[party][distributionId].remainingMemberSupply;
    }

    function emergencyRemoveDistribution(ITokenDistributorParty party, uint256 distributionId) onlyPartyDao onlyIfEmergencyActionsAllowed public {
        delete _distributionStates[party][distributionId];
    }

    function emergencyWithdraw(
        IERC20 token, address payable recipient, uint256 amount
    ) onlyPartyDao onlyIfEmergencyActionsAllowed public {
        _transfer(token, recipient, amount);
    }

    function disableEmergencyActions() onlyPartyDao public {
        allowEmergencyActions = false;
    }

    // For receiving ETH
    receive() external payable {}

    function _transfer(IERC20 token, address payable recipient, uint256 amount)
        private
    {
        // Reduce stored token balance.
        _storedBalances[token] -= amount;
        if (token == ETH_TOKEN) {
            recipient.transferEth(amount);
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
