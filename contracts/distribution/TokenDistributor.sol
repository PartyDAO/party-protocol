// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC20.sol";
import "../tokens/IERC1155.sol";
import "../utils/LibAddress.sol";
import "../utils/LibERC20Compat.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibSafeCast.sol";

import "./ITokenDistributor.sol";

/// @notice Creates token distributions for parties.
contract TokenDistributor is ITokenDistributor {
    using LibAddress for address payable;
    using LibERC20Compat for IERC20;
    using LibRawResult for bytes;
    using LibSafeCast for uint256;

    struct DistributionState {
        // The remaining member supply.
        uint128 remainingMemberSupply;
        // The 15-byte hash of the DistributionInfo.
        bytes15 distributionHash15;
        // Whether partyDao has claimed its distribution share.
        bool wasFeeClaimed;
        // Whether a governance token has claimed its distribution share.
        mapping (uint256 => bool) hasPartyTokenClaimed;
    }

    address private constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IGlobals public immutable GLOBALS;

    /// @notice Whether the DAO can call emergency functions.
    bool public allowEmergencyActions = true;
    /// @notice Last distribution ID for a party.
    mapping(ITokenDistributorParty => uint256) public lastDistributionIdPerParty;
    /// Last known balance of a token, identified by an ID derived from the token.
    /// Gets lazily updated when creating and claiming a distribution (transfers).
    /// Allows one to simply transfer and call `createDistribution()` without
    /// fussing with allowances.
    mapping(bytes32 => uint256) private _storedBalances;
    // tokenDistributorParty => distributionId => DistributionState
    mapping(ITokenDistributorParty => mapping(uint256 => DistributionState)) private _distributionStates;

    // msg.sender == DAO
    modifier onlyPartyDao() {
        {
            address partyDao = GLOBALS.getAddress(LibGlobals.GLOBAL_DAO_WALLET);
            if (msg.sender != partyDao) {
                revert OnlyPartyDaoError(msg.sender, partyDao);
            }
        }
        _;
    }

    // allowEmergencyActions == true
    modifier onlyIfEmergencyActionsAllowed() {
        if (!allowEmergencyActions) {
            revert EmergencyActionsNotAllowed();
        }
        _;
    }

    constructor(IGlobals globals) {
        GLOBALS = globals;
    }

    /// @inheritdoc ITokenDistributor
    function createNativeDistribution(address payable feeRecipient, uint16 feeBps)
        external
        payable
        returns (DistributionInfo memory info)
    {
        info = _createDistribution(
            TokenType.Native,
            NATIVE_TOKEN_ADDRESS,
            0,
            address(this).balance,
            feeRecipient,
            feeBps
        );
        emit DistributionCreated(info);
    }

    /// @inheritdoc ITokenDistributor
    function createErc20Distribution(
        IERC20 token,
        address payable feeRecipient,
        uint16 feeBps
    )
        external
        returns (DistributionInfo memory info)
    {
        info = _createDistribution(
            TokenType.Erc20,
            address(token),
            0,
            token.balanceOf(address(this)),
            feeRecipient,
            feeBps
        );
        emit DistributionCreated(info);
    }

    /// @inheritdoc ITokenDistributor
    function createErc1155Distribution(
        IERC1155 token,
        uint256 tokenId,
        address payable feeRecipient,
        uint16 feeBps
    )
        external
        returns (DistributionInfo memory info)
    {
        info = _createDistribution(
            TokenType.Erc1155,
            address(token),
            tokenId,
            token.balanceOf(address(this), tokenId),
            feeRecipient,
            feeBps
        );
        emit DistributionCreated(info);
    }

    /// @inheritdoc ITokenDistributor
    function claim(DistributionInfo calldata info, uint256 partyTokenId)
        external
        returns (uint128 amountClaimed)
    {
        // Caller must own the party token.
        {
            address ownerOfPartyToken = info.party.ownerOf(partyTokenId);
            if (msg.sender != ownerOfPartyToken) {
                revert MustOwnTokenError(msg.sender, ownerOfPartyToken, partyTokenId);
            }
        }
        // DistributionInfo must be correct for this distribution ID.
        DistributionState storage state = _distributionStates[info.party][info.distributionId];
        if (state.distributionHash15 != _getDistributionHash(info)) {
            revert InvalidDistributionInfoError(info);
        }
        // The partyTokenId must not have claimed its distribution yet.
        if (state.hasPartyTokenClaimed[partyTokenId]) {
            revert DistributionAlreadyClaimedByTokenError(info.distributionId, partyTokenId);
        }
        // Mark the partyTokenId as having claimed their distribution.
        state.hasPartyTokenClaimed[partyTokenId] = true;

        // Compute amount owed to partyTokenId.
        amountClaimed = getClaimAmount(info, partyTokenId);

        // Cap at the remaining member supply. Otherwise a malicious
        // party could drain more than the distribution supply.
        uint128 remainingMemberSupply = state.remainingMemberSupply;
        amountClaimed = amountClaimed > remainingMemberSupply
            ? remainingMemberSupply
            : amountClaimed;
        state.remainingMemberSupply = remainingMemberSupply - amountClaimed;

        // Transfer tokens owed.
        _transfer(
            info.tokenType,
            info.token,
            info.tokenId,
            payable(msg.sender),
            amountClaimed
        );
        emit DistributionClaimedByToken(info, partyTokenId, msg.sender, amountClaimed);
    }

    /// @inheritdoc ITokenDistributor
    function claimFee(DistributionInfo calldata info, address payable recipient)
        external
    {
        // DistributionInfo must be correct for this distribution ID.
        DistributionState storage state = _distributionStates[info.party][info.distributionId];
        if (state.distributionHash15 != _getDistributionHash(info)) {
            revert InvalidDistributionInfoError(info);
        }
        // Caller must be the fee recipient.
        if (info.feeRecipient != msg.sender) {
            revert OnlyFeeRecipientError(msg.sender, info.feeRecipient);
        }
        // Must not have claimed the fee yet.
        if (state.wasFeeClaimed) {
            revert DistributionFeeAlreadyClaimedError(info.distributionId);
        }
        // Mark the fee as claimed.
        state.wasFeeClaimed = true;
        // Transfer the tokens owed.
        _transfer(
            info.tokenType,
            info.token,
            info.tokenId,
            recipient,
            info.fee
        );
        emit DistributionClaimedByPartyDao(info, recipient, info.fee);
    }

    /// @inheritdoc ITokenDistributor
    function getClaimAmount(DistributionInfo calldata info, uint256 partyTokenId)
        public
        view
        returns (uint128)
    {
        // getDistributionShareOf() is the fraction of the memberSupply partyTokenId
        // is entitled to, scaled by 1e18.
        return (
            uint256(info.party.getDistributionShareOf(partyTokenId))
            * info.memberSupply
            / 1e18
        ).safeCastUint256ToUint128();
    }

    /// @inheritdoc ITokenDistributor
    function wasFeeClaimed(ITokenDistributorParty party, uint256 distributionId)
        external
        view
        returns (bool)
    {
        return _distributionStates[party][distributionId].wasFeeClaimed;
    }

    /// @inheritdoc ITokenDistributor
    function hasPartyTokenIdClaimed(
        ITokenDistributorParty party,
        uint256 partyTokenId,
        uint256 distributionId
    )
        external
        view returns (bool)
    {
        return _distributionStates[party][distributionId].hasPartyTokenClaimed[partyTokenId];
    }

    /// @inheritdoc ITokenDistributor
    function getRemainingMemberSupply(
        ITokenDistributorParty party,
        uint256 distributionId
    )
        external
        view
        returns (uint128)
    {
        return _distributionStates[party][distributionId].remainingMemberSupply;
    }

    /// @inheritdoc ITokenDistributor
    function emergencyRemoveDistribution(
        ITokenDistributorParty party,
        uint256 distributionId
    )
        onlyPartyDao
        onlyIfEmergencyActionsAllowed
        external
    {
        delete _distributionStates[party][distributionId];
    }

    /// @inheritdoc ITokenDistributor
    function emergencyWithdraw(
        TokenType tokenType,
        address token,
        uint256 tokenId,
        address payable recipient,
        uint256 amount
    )
        onlyPartyDao
        onlyIfEmergencyActionsAllowed
        external
    {
        _transfer(tokenType, token, tokenId, recipient, amount);
    }

    function disableEmergencyActions() onlyPartyDao external {
        allowEmergencyActions = false;
    }

    // For receiving ETH
    receive() external payable {}

    function _createDistribution(
        TokenType tokenType,
        address token,
        uint256 tokenId,
        uint256 currentTokenBalance,
        address payable feeRecipient,
        uint16 feeBps
    )
        private
        returns (DistributionInfo memory info)
    {
        if (feeBps > 1e4) {
            revert InvalidFeeBps(feeBps);
        }
        bytes32 balanceId = _getBalanceId(tokenType, token, tokenId);
        uint128 supply = (currentTokenBalance - _storedBalances[balanceId])
            .safeCastUint256ToUint128();
        // Supply must be nonzero.
        if (supply == 0) {
            revert InvalidDistributionSupply(supply);
        }
        // Update stored balance.
        _storedBalances[balanceId] = currentTokenBalance;

        // Create a distribution.
        ITokenDistributorParty party = ITokenDistributorParty(msg.sender);
        uint256 distId = ++lastDistributionIdPerParty[party];
        uint128 fee = supply * feeBps / 1e4;
        uint128 memberSupply = supply - fee;

        info = DistributionInfo({
            tokenType: tokenType,
            distributionId: distId,
            token: token,
            tokenId: tokenId,
            party: party,
            memberSupply: memberSupply,
            feeRecipient: feeRecipient,
            fee: fee
        });
        (
            _distributionStates[party][distId].distributionHash15,
            _distributionStates[party][distId].remainingMemberSupply
        ) = (_getDistributionHash(info), memberSupply);
        emit DistributionCreated(info);
    }

    function _transfer(
        TokenType tokenType,
        address token,
        uint256 tokenId,
        address payable recipient,
        uint256 amount
    )
        private
    {
        bytes32 balanceId = _getBalanceId(tokenType, token, tokenId);
        // Reduce stored token balance.
        _storedBalances[balanceId] -= amount;
        if (tokenType == TokenType.Native) {
            recipient.transferEth(amount);
        } else if (tokenType == TokenType.Erc20) {
            IERC20(token).compatTransfer(recipient, amount);
        } else {
            assert(tokenType == TokenType.Erc1155);
            IERC1155(token).safeTransferFrom(address(this), recipient, tokenId, amount, "");
        }
    }

    function _getDistributionHash(DistributionInfo memory info)
        private
        pure
        returns (bytes15 hash)
    {
        assembly {
            hash := and(
                keccak256(info, 0x100),
                0xffffffffffffffffffffffffffffff0000000000000000000000000000000000
            )
        }
    }

    function _getBalanceId(TokenType tokenType, address token, uint256 tokenId)
        private
        pure
        returns (bytes32 balanceId)
    {
        if (tokenType == TokenType.Native) {
            return bytes32(uint256(uint160(NATIVE_TOKEN_ADDRESS)));
        }
        if (tokenType == TokenType.Erc20) {
            return bytes32(uint256(uint160(token)));
        }
        assert(tokenType == TokenType.Erc1155);
        assembly {
            mstore(0x00, token)
            mstore(0x20, tokenId)
            balanceId := keccak256(0x00, 0x20)
        }
    }
}
