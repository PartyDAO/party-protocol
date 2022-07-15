// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC20.sol";
import "../tokens/IERC1155.sol";
import "../tokens/ERC1155TokenReceiver.sol";
import "../utils/LibAddress.sol";
import "../utils/LibERC20Compat.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibSafeCast.sol";

import "./ITokenDistributor.sol";

/// @notice Creates token distributions for parties.
contract TokenDistributor is ITokenDistributor, ERC1155TokenReceiver {
    using LibAddress for address payable;
    using LibERC20Compat for IERC20;
    using LibRawResult for bytes;
    using LibSafeCast for uint256;

    struct DistributionState {
        // The remaining member supply.
        uint128 remainingMemberSupply;
        // The 15-byte hash of the DistributionInfo.
        bytes15 distributionHash15;
        // Whether the distribution's feeRecipient has claimed its fee.
        bool wasFeeClaimed;
        // Whether a governance token has claimed its distribution share.
        mapping (uint256 => bool) hasPartyTokenClaimed;
    }

    // Args for _createDistribution()
    struct CreateDistributionArgs {
        ITokenDistributorParty party;
        TokenType tokenType;
        address token;
        uint256 erc1155TokenId;
        uint256 currentTokenBalance;
        address payable feeRecipient;
        uint16 feeBps;
    }

    error OnlyPartyDaoError(address notDao, address partyDao);
    error OnlyPartyDaoAuthorityError(address notDaoAuthority);
    error InvalidDistributionInfoError(DistributionInfo info);
    error DistributionAlreadyClaimedByPartyTokenError(uint256 distributionId, uint256 partyTokenId);
    error DistributionFeeAlreadyClaimedError(uint256 distributionId);
    error MustOwnTokenError(address sender, address expectedOwner, uint256 partyTokenId);
    error EmergencyActionsNotAllowedError();
    error InvalidDistributionSupplyError(uint128 supply);
    error OnlyFeeRecipientError(address caller, address feeRecipient);
    error InvalidFeeBpsError(uint16 feeBps);

    address private constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IGlobals public immutable GLOBALS;

    /// @notice Whether the DAO is no longer allowed to call emergency functions.
    bool public emergencyActionsDisabled;
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

    // emergencyActionsDisabled == false
    modifier onlyIfEmergencyActionsAllowed() {
        if (emergencyActionsDisabled) {
            revert EmergencyActionsNotAllowedError();
        }
        _;
    }

    constructor(IGlobals globals) {
        GLOBALS = globals;
    }

    /// @notice For receiving ETH
    receive() external payable {}

    /// @inheritdoc ITokenDistributor
    function createNativeDistribution(
        ITokenDistributorParty party,
        address payable feeRecipient,
        uint16 feeBps
    )
        external
        payable
        returns (DistributionInfo memory info)
    {
        info = _createDistribution(CreateDistributionArgs({
            party: party,
            tokenType: TokenType.Native,
            token: NATIVE_TOKEN_ADDRESS,
            erc1155TokenId: 0,
            currentTokenBalance: address(this).balance,
            feeRecipient: feeRecipient,
            feeBps: feeBps
        }));
    }

    /// @inheritdoc ITokenDistributor
    function createErc20Distribution(
        IERC20 token,
        ITokenDistributorParty party,
        address payable feeRecipient,
        uint16 feeBps
    )
        external
        returns (DistributionInfo memory info)
    {
        info = _createDistribution(CreateDistributionArgs({
            party: party,
            tokenType: TokenType.Erc20,
            token: address(token),
            erc1155TokenId: 0,
            currentTokenBalance: token.balanceOf(address(this)),
            feeRecipient: feeRecipient,
            feeBps: feeBps
        }));
    }

    /// @inheritdoc ITokenDistributor
    function createErc1155Distribution(
        IERC1155 token,
        uint256 erc1155TokenId,
        ITokenDistributorParty party,
        address payable feeRecipient,
        uint16 feeBps
    )
        external
        returns (DistributionInfo memory info)
    {
        info = _createDistribution(CreateDistributionArgs({
            party: party,
            tokenType: TokenType.Erc1155,
            token: address(token),
            erc1155TokenId: erc1155TokenId,
            currentTokenBalance: token.balanceOf(address(this), erc1155TokenId),
            feeRecipient: feeRecipient,
            feeBps: feeBps
        }));
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
            revert DistributionAlreadyClaimedByPartyTokenError(info.distributionId, partyTokenId);
        }
        // Mark the partyTokenId as having claimed their distribution.
        state.hasPartyTokenClaimed[partyTokenId] = true;

        // Compute amount owed to partyTokenId.
        amountClaimed = getClaimAmount(info.party, info.memberSupply, partyTokenId);

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
            info.erc1155TokenId,
            payable(msg.sender),
            amountClaimed
        );
        emit DistributionClaimedByPartyToken(
            info.party,
            partyTokenId,
            msg.sender,
            info.tokenType,
            info.token,
            info.erc1155TokenId,
            amountClaimed
        );
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
            info.erc1155TokenId,
            recipient,
            info.fee
        );
        emit DistributionFeeClaimed(
            info.party,
            info.feeRecipient,
            info.tokenType,
            info.token,
            info.erc1155TokenId,
            info.fee
        );
    }

    /// @inheritdoc ITokenDistributor
    function getClaimAmount(
        ITokenDistributorParty party,
        uint256 memberSupply,
        uint256 partyTokenId
    )
        public
        view
        returns (uint128)
    {
        // getDistributionShareOf() is the fraction of the memberSupply partyTokenId
        // is entitled to, scaled by 1e18.
        // We round up here to prevent dust amounts getting trapped in this contract.
        return (
            (
                uint256(party.getDistributionShareOf(partyTokenId))
                * memberSupply
                + (1e18 - 1)
            )
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

    /// @notice DAO-only function to clear a distribution in case something goes wrong.
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

    /// @notice DAO-only function to withdraw tokens in case something goes wrong.
    function emergencyWithdraw(
        TokenType tokenType,
        address token,
        uint256 erc1155TokenId,
        address payable recipient,
        uint256 amount
    )
        onlyPartyDao
        onlyIfEmergencyActionsAllowed
        external
    {
        _transfer(tokenType, token, erc1155TokenId, recipient, amount);
    }

    /// @notice DAO-only function to disable emergency functions forever.
    function disableEmergencyActions() onlyPartyDao external {
        emergencyActionsDisabled = true;
    }

    function _createDistribution(CreateDistributionArgs memory args)
        private
        returns (DistributionInfo memory info)
    {
        if (args.feeBps > 1e4) {
            revert InvalidFeeBpsError(args.feeBps);
        }
        uint128 supply;
        {
            bytes32 balanceId = _getBalanceId(args.tokenType, args.token, args.erc1155TokenId);
            supply = (args.currentTokenBalance - _storedBalances[balanceId])
                .safeCastUint256ToUint128();
            // Supply must be nonzero.
            if (supply == 0) {
                revert InvalidDistributionSupplyError(supply);
            }
            // Update stored balance.
            _storedBalances[balanceId] = args.currentTokenBalance;
        }

        // Create a distribution.
        uint128 fee = supply * args.feeBps / 1e4;
        uint128 memberSupply = supply - fee;

        info = DistributionInfo({
            tokenType: args.tokenType,
            distributionId: ++lastDistributionIdPerParty[args.party],
            token: args.token,
            erc1155TokenId: args.erc1155TokenId,
            party: args.party,
            memberSupply: memberSupply,
            feeRecipient: args.feeRecipient,
            fee: fee
        });
        (
            _distributionStates[args.party][info.distributionId].distributionHash15,
            _distributionStates[args.party][info.distributionId].remainingMemberSupply
        ) = (_getDistributionHash(info), memberSupply);
        emit DistributionCreated(args.party, info);
    }

    function _transfer(
        TokenType tokenType,
        address token,
        uint256 erc1155TokenId,
        address payable recipient,
        uint256 amount
    )
        private
    {
        bytes32 balanceId = _getBalanceId(tokenType, token, erc1155TokenId);
        // Reduce stored token balance.
        _storedBalances[balanceId] -= amount;
        if (tokenType == TokenType.Native) {
            recipient.transferEth(amount);
        } else if (tokenType == TokenType.Erc20) {
            IERC20(token).compatTransfer(recipient, amount);
        } else {
            assert(tokenType == TokenType.Erc1155);
            IERC1155(token).safeTransferFrom(address(this), recipient, erc1155TokenId, amount, "");
        }
    }

    function _getDistributionHash(DistributionInfo memory info)
        internal
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

    function _getBalanceId(TokenType tokenType, address token, uint256 erc1155TokenId)
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
            mstore(0x20, erc1155TokenId)
            balanceId := keccak256(0x00, 0x40)
        }
    }
}
