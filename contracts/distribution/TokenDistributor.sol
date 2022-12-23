// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "../globals/IGlobals.sol";
import "../globals/LibGlobals.sol";
import "../tokens/IERC20.sol";
import "../utils/LibAddress.sol";
import "../utils/LibERC20Compat.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibSafeCast.sol";

import "./ITokenDistributor.sol";

/// @notice Creates token distributions for parties (or any contract that
///         implements `ITokenDistributorParty`).
contract TokenDistributor is ITokenDistributor {
    using LibAddress for address payable;
    using LibERC20Compat for IERC20;
    using LibRawResult for bytes;
    using LibSafeCast for uint256;

    struct DistributionState {
        // The hash of the `DistributionInfo`.
        bytes32 distributionHash;
        // The remaining member supply.
        uint128 remainingMemberSupply;
        // Whether the distribution's feeRecipient has claimed its fee.
        bool wasFeeClaimed;
        // Whether a governance token has claimed its distribution share.
        mapping(uint256 => bool) hasPartyTokenClaimed;
    }

    // Arguments for `_createDistribution()`.
    struct CreateDistributionArgs {
        ITokenDistributorParty party;
        TokenType tokenType;
        address token;
        uint256 currentTokenBalance;
        address payable feeRecipient;
        uint16 feeBps;
    }

    event EmergencyExecute(address target, bytes data);

    error OnlyPartyDaoError(address notDao, address partyDao);
    error InvalidDistributionInfoError(DistributionInfo info);
    error DistributionAlreadyClaimedByPartyTokenError(uint256 distributionId, uint256 partyTokenId);
    error DistributionFeeAlreadyClaimedError(uint256 distributionId);
    error MustOwnTokenError(address sender, address expectedOwner, uint256 partyTokenId);
    error EmergencyActionsNotAllowedError();
    error InvalidDistributionSupplyError(uint128 supply);
    error OnlyFeeRecipientError(address caller, address feeRecipient);
    error InvalidFeeBpsError(uint16 feeBps);

    // Token address used to indicate a native distribution (i.e. distribution of ETH).
    address private constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice The `Globals` contract storing global configuration values. This contract
    ///         is immutable and it’s address will never change.
    IGlobals public immutable GLOBALS;
    /// @notice Timestamp when the DAO is no longer allowed to call emergency functions.
    uint40 public immutable EMERGENCY_DISABLED_TIMESTAMP;

    /// @notice Last distribution ID for a party.
    mapping(ITokenDistributorParty => uint256) public lastDistributionIdPerParty;
    /// Last known balance of a token, identified by an ID derived from the token.
    /// Gets lazily updated when creating and claiming a distribution (transfers).
    /// Allows one to simply transfer and call `createDistribution()` without
    /// fussing with allowances.
    mapping(bytes32 => uint256) private _storedBalances;
    // tokenDistributorParty => distributionId => DistributionState
    mapping(ITokenDistributorParty => mapping(uint256 => DistributionState))
        private _distributionStates;

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
        if (block.timestamp > EMERGENCY_DISABLED_TIMESTAMP) {
            revert EmergencyActionsNotAllowedError();
        }
        _;
    }

    // Set the `Globals` contract.
    constructor(IGlobals globals, uint40 emergencyDisabledTimestamp) {
        GLOBALS = globals;
        EMERGENCY_DISABLED_TIMESTAMP = emergencyDisabledTimestamp;
    }

    /// @inheritdoc ITokenDistributor
    function createNativeDistribution(
        ITokenDistributorParty party,
        address payable feeRecipient,
        uint16 feeBps
    ) external payable returns (DistributionInfo memory info) {
        info = _createDistribution(
            CreateDistributionArgs({
                party: party,
                tokenType: TokenType.Native,
                token: NATIVE_TOKEN_ADDRESS,
                currentTokenBalance: address(this).balance,
                feeRecipient: feeRecipient,
                feeBps: feeBps
            })
        );
    }

    /// @inheritdoc ITokenDistributor
    function createErc20Distribution(
        IERC20 token,
        ITokenDistributorParty party,
        address payable feeRecipient,
        uint16 feeBps
    ) external returns (DistributionInfo memory info) {
        info = _createDistribution(
            CreateDistributionArgs({
                party: party,
                tokenType: TokenType.Erc20,
                token: address(token),
                currentTokenBalance: token.balanceOf(address(this)),
                feeRecipient: feeRecipient,
                feeBps: feeBps
            })
        );
    }

    /// @inheritdoc ITokenDistributor
    function claim(
        DistributionInfo calldata info,
        uint256 partyTokenId
    ) public returns (uint128 amountClaimed) {
        // Caller must own the party token.
        {
            address ownerOfPartyToken = info.party.ownerOf(partyTokenId);
            if (msg.sender != ownerOfPartyToken) {
                revert MustOwnTokenError(msg.sender, ownerOfPartyToken, partyTokenId);
            }
        }
        // DistributionInfo must be correct for this distribution ID.
        DistributionState storage state = _distributionStates[info.party][info.distributionId];
        if (state.distributionHash != _getDistributionHash(info)) {
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
        _transfer(info.tokenType, info.token, payable(msg.sender), amountClaimed);
        emit DistributionClaimedByPartyToken(
            info.party,
            partyTokenId,
            msg.sender,
            info.tokenType,
            info.token,
            amountClaimed
        );
    }

    /// @inheritdoc ITokenDistributor
    function claimFee(DistributionInfo calldata info, address payable recipient) public {
        // DistributionInfo must be correct for this distribution ID.
        DistributionState storage state = _distributionStates[info.party][info.distributionId];
        if (state.distributionHash != _getDistributionHash(info)) {
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
        _transfer(info.tokenType, info.token, recipient, info.fee);
        emit DistributionFeeClaimed(
            info.party,
            info.feeRecipient,
            info.tokenType,
            info.token,
            info.fee
        );
    }

    /// @inheritdoc ITokenDistributor
    function batchClaim(
        DistributionInfo[] calldata infos,
        uint256[] calldata partyTokenIds
    ) external returns (uint128[] memory amountsClaimed) {
        amountsClaimed = new uint128[](infos.length);
        for (uint256 i = 0; i < infos.length; ++i) {
            amountsClaimed[i] = claim(infos[i], partyTokenIds[i]);
        }
    }

    /// @inheritdoc ITokenDistributor
    function batchClaimFee(
        DistributionInfo[] calldata infos,
        address payable[] calldata recipients
    ) external {
        for (uint256 i = 0; i < infos.length; ++i) {
            claimFee(infos[i], recipients[i]);
        }
    }

    /// @inheritdoc ITokenDistributor
    function getClaimAmount(
        ITokenDistributorParty party,
        uint256 memberSupply,
        uint256 partyTokenId
    ) public view returns (uint128) {
        // getDistributionShareOf() is the fraction of the memberSupply partyTokenId
        // is entitled to, scaled by 1e18.
        // We round up here to prevent dust amounts getting trapped in this contract.
        return
            ((uint256(party.getDistributionShareOf(partyTokenId)) * memberSupply + (1e18 - 1)) /
                1e18).safeCastUint256ToUint128();
    }

    /// @inheritdoc ITokenDistributor
    function wasFeeClaimed(
        ITokenDistributorParty party,
        uint256 distributionId
    ) external view returns (bool) {
        return _distributionStates[party][distributionId].wasFeeClaimed;
    }

    /// @inheritdoc ITokenDistributor
    function hasPartyTokenIdClaimed(
        ITokenDistributorParty party,
        uint256 partyTokenId,
        uint256 distributionId
    ) external view returns (bool) {
        return _distributionStates[party][distributionId].hasPartyTokenClaimed[partyTokenId];
    }

    /// @inheritdoc ITokenDistributor
    function getRemainingMemberSupply(
        ITokenDistributorParty party,
        uint256 distributionId
    ) external view returns (uint128) {
        return _distributionStates[party][distributionId].remainingMemberSupply;
    }

    /// @notice As the DAO, execute an arbitrary delegatecall from this contract.
    /// @dev Emergency actions must not be revoked for this to work.
    /// @param targetAddress The contract to delegatecall into.
    /// @param targetCallData The data to pass to the call.
    function emergencyExecute(
        address targetAddress,
        bytes calldata targetCallData
    ) external onlyPartyDao onlyIfEmergencyActionsAllowed {
        (bool success, bytes memory res) = targetAddress.delegatecall(targetCallData);
        if (!success) {
            res.rawRevert();
        }
        emit EmergencyExecute(targetAddress, targetCallData);
    }

    function _createDistribution(
        CreateDistributionArgs memory args
    ) private returns (DistributionInfo memory info) {
        if (args.feeBps > 1e4) {
            revert InvalidFeeBpsError(args.feeBps);
        }
        uint128 supply;
        {
            bytes32 balanceId = _getBalanceId(args.tokenType, args.token);
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
        uint128 fee = (supply * args.feeBps) / 1e4;
        uint128 memberSupply = supply - fee;

        info = DistributionInfo({
            tokenType: args.tokenType,
            distributionId: ++lastDistributionIdPerParty[args.party],
            token: args.token,
            party: args.party,
            memberSupply: memberSupply,
            feeRecipient: args.feeRecipient,
            fee: fee
        });
        (
            _distributionStates[args.party][info.distributionId].distributionHash,
            _distributionStates[args.party][info.distributionId].remainingMemberSupply
        ) = (_getDistributionHash(info), memberSupply);
        emit DistributionCreated(args.party, info);
    }

    function _transfer(
        TokenType tokenType,
        address token,
        address payable recipient,
        uint256 amount
    ) private {
        bytes32 balanceId = _getBalanceId(tokenType, token);
        // Reduce stored token balance.
        uint256 storedBalance = _storedBalances[balanceId] - amount;
        // Temporarily set to max as a reentrancy guard. An interesing attack
        // could occur if we didn't do this where an attacker could `claim()` and
        // reenter upon transfer (eg. in the `tokensToSend` hook of an ERC777) to
        // `createERC20Distribution()`. Since the `balanceOf(address(this))`
        // would not of been updated yet, the supply would be miscalculated and
        // the attacker would create a distribution that essentially steals from
        // the last distribution they were claiming from. Here, we prevent that
        // by causing an arithmetic underflow with the supply calculation if
        // this were to be attempted.
        _storedBalances[balanceId] = type(uint256).max;
        if (tokenType == TokenType.Native) {
            recipient.transferEth(amount);
        } else {
            assert(tokenType == TokenType.Erc20);
            IERC20(token).compatTransfer(recipient, amount);
        }
        _storedBalances[balanceId] = storedBalance;
    }

    function _getDistributionHash(
        DistributionInfo memory info
    ) internal pure returns (bytes32 hash) {
        assembly {
            hash := keccak256(info, 0xe0)
        }
    }

    function _getBalanceId(
        TokenType tokenType,
        address token
    ) private pure returns (bytes32 balanceId) {
        if (tokenType == TokenType.Native) {
            return bytes32(uint256(uint160(NATIVE_TOKEN_ADDRESS)));
        }
        assert(tokenType == TokenType.Erc20);
        return bytes32(uint256(uint160(token)));
    }
}
