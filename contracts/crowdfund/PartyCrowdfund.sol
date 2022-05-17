// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

import "../utils/LibAddress.sol";
import "../utils/LibRawResult.sol";
import "../utils/LibSafeCast.sol";
import "../tokens/ERC721Receiver.sol";
import "../party/Party.sol";
import "../globals/IGlobals.sol";

import "./PartyCrowdfundNFT.sol";

// Base contract for PartyBid/PartyBuy.
// Holds post-win/loss logic. E.g., burning contribution NFTs and creating a
// party after winning.
abstract contract PartyCrowdfund is ERC721Receiver, PartyCrowdfundNFT {
    using LibRawResult for bytes;
    using LibSafeCast for uint256;
    using LibAddress for address payable;

    enum CrowdfundLifecycle {
        Invalid,
        Active,
        Lost,
        Won
    }

    struct CrowdfundInitOptions {
        string name;
        string symbol;
        Party.PartyOptions partyOptions;
        address payable splitRecipient;
        uint16 splitBps;
        address initialContributor;
        address initialDelegate;
    }

    struct Contribution {
        uint128 previousTotalContributions;
        uint128 amount;
    }

    error PartyAlreadyExistsError(Party party);
    error WrongLifecycleError(CrowdfundLifecycle lc);
    error CrowdfundNotOverError(CrowdfundLifecycle lc);
    error InvalidPartyOptionsError(bytes32 partyOptionsHash, bytes32 expectedPartyOptionsHash);
    error InvalidDelegateError();
    error NoPartyError();

    event DaoClaimed(address recipient, uint256 amount);
    event Burned(address contributor, uint256 ethUsed, uint256 votingPower);
    event Contributed(address contributor, uint256 amount, address delegate);

    IGlobals private immutable _GLOBALS;

    // The party instance created by `_createParty()`, if any.
    Party public party;
    // How much governance power to reserve for `splitRecipient`,
    // in bps, where 1000 = 100%.
    uint16 public splitBps;
    // Who will receive a reserved portion of governance power.
    address payable public splitRecipient;
    // Hash of PartyOptions passed into initialize().
    // The PartyOptions passed into `_createParty()` must match.
    bytes32 public partyOptionsHash;
    // The total (recorded) ETH contributed to this crowdfund.
    uint128 public totalContributions;
    // Who a contributor last delegated to.
    mapping (address => address) private _delegationsByContributor;
    // Array of contributions by a contributor.
    // One is created for every contribution made.
    mapping (address => Contribution[]) private _contributionsByContributor;

    constructor(IGlobals globals) PartyCrowdfundNFT(globals) {
        _GLOBALS = globals;
    }

    // Must be called once by freshly deployed PartyCrowdfundProxy instances.
    function _initialize(CrowdfundInitOptions memory opts)
        internal
    {
        PartyCrowdfundNFT.initialize(opts.name, opts.symbol);
        partyOptionsHash = _hashPartyOptions(opts.partyOptions);
        splitRecipient = opts.splitRecipient;
        splitBps = opts.splitBps;
        // If the deployer passed in some ETH during deployment, credit them.
        uint128 initialBalance = address(this).balance.safeCastUint256ToUint128();
        if (initialBalance > 0) {
            // If this contract has ETH, either passed in during deployment or
            // pre-existing, credit it to the `initialContributor`.
            _addContribution(opts.initialContributor, initialBalance, opts.initialDelegate, 0);
        }
    }

    // Burns CF tokens owned by `owner` AFTER the CF has ended.
    // If the party has won, someone needs to call `_createParty()` first. After
    // which, `burn()` will refund unused ETH and mint governance tokens for the
    // given `contributor`.
    // If the party has lost, this will only refund unused ETH (all of it) for
    // the given `contributor`.
    function burn(address payable contributor)
        public
    {
        return _burn(contributor, getCrowdfundLifecycle(), party);
    }

    // `burn()` in batch form.
    function batchBurn(address payable[] calldata contributors)
        external
    {
        Party party_ = party;
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        for (uint256 i = 0; i < contributors.length; ++i) {
            _burn(contributors[i], lc, party_);
        }
    }

    // Contribute and/or delegate.
    // TODO: Should contributor not be a param?
    function contribute(address contributor, address delegate)
        public
        payable
    {
        _addContribution(
            contributor,
            msg.value.safeCastUint256ToUint128(),
            delegate,
            // Use this.balance instead of separately tracking registered
            // total contributions. Sure, someone could force ETH into
            // this contract which would effectively create a contribution that
            // can never result in a governance NFT, meaning the party
            // can never reach 100% consensus. But they perform the same
            // grief by contributing normally and never participating in
            // governance.
            (address(this).balance - msg.value).safeCastUint256ToUint128()
        );
    }

    // Contribute, reusing the last delegate of the sender or
    // the sender itself if not set.
    receive() external payable {
        // If the sender already delegated before then use that delegate.
        // Otherwise delegate to the sender.
        address delegate = _delegationsByContributor[msg.sender];
        delegate = delegate == address(0) ? msg.sender : delegate;
        _addContribution(
            msg.sender,
            msg.value.safeCastUint256ToUint128(),
            delegate,
            (address(this).balance - msg.value).safeCastUint256ToUint128()
        );
    }

    // Need to define this because of nonlinear base definitions.
    function supportsInterface(bytes4 interfaceId)
        public
        override(ERC721Receiver, PartyCrowdfundNFT)
        pure
        returns (bool)
    {
        if (ERC721Receiver.supportsInterface(interfaceId)) {
            return true;
        }
        return PartyCrowdfundNFT.supportsInterface(interfaceId);
    }

    // This will only be called off-chain so doesn't have to be optimal.
    function getContributorInfo(address contributor)
        external
        view
        returns (
            uint256 ethContributed,
            uint256 ethUsed,
            uint256 ethOwed,
            uint256 votingPower
        )
    {
        CrowdfundLifecycle lc = getCrowdfundLifecycle();
        Contribution[] storage contributions = _contributionsByContributor[contributor];
        uint256 numContributions = contributions.length;
        for (uint256 i = 0; i < numContributions; ++i) {
            ethContributed += contributions[i].amount;
        }
        if (lc == CrowdfundLifecycle.Won || lc == CrowdfundLifecycle.Lost) {
            (ethUsed, ethOwed, votingPower) = _getFinalContribution(contributor);
        }
    }

    function getCrowdfundLifecycle() public virtual view returns (CrowdfundLifecycle);

    // Get the final sale price (not including party fees, splits, etc) of the
    // bought assets.
    function _getFinalPrice() internal virtual view returns (uint256);

    // Can be called after a party has won.
    // Deploys and initializes a a `Party` instance via the `PartyFactory`
    // and transfers the bought NFT to it.
    // After calling this, anyone can burn CF tokens on a contributor's behalf
    // with the `burn()` function.
    function _createParty(
        Party.PartyOptions memory opts,
        IERC721[] memory preciousTokens,
        uint256[] memory preciousTokenIds
    )
        internal
        returns (Party party_)
    {
        if (party != Party(payable(0))) {
            revert PartyAlreadyExistsError(party);
        }
        {
            bytes32 partyOptionsHash_ = _hashPartyOptions(opts);
            if (partyOptionsHash_ != partyOptionsHash) {
                revert InvalidPartyOptionsError(partyOptionsHash_, partyOptionsHash);
            }
        }
        party = party_ = _getPartyFactory()
            .createParty(address(this), opts, preciousTokens, preciousTokenIds);
        for (uint256 i = 0; i < preciousTokens.length; ++i) {
            preciousTokens[i].transferFrom(address(this), address(party_), preciousTokenIds[i]);
        }
    }

    // Overloaded single token wrapper for _createParty()
    function _createParty(
        Party.PartyOptions memory opts,
        IERC721 preciousToken,
        uint256 preciousTokenId
    )
        internal
        returns (Party party_)
    {
        IERC721[] memory tokens = new IERC721[](1);
        tokens[0] = preciousToken;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = preciousTokenId;
        return _createParty(opts, tokens, tokenIds);
    }

    function _hashPartyOptions(Party.PartyOptions memory opts)
        private
        pure
        returns (bytes32 h)
    {
        bytes32 governanceOptsHostsHash = keccak256(abi.encode(opts.governance.hosts));
        bytes32 nameHash = keccak256(bytes(opts.name));
        bytes32 symbolHash = keccak256(bytes(opts.symbol));
        // Hash in place.
        assembly {
            let oldGovernanceOptsHostFieldValue := mload(opts)
            let oldNameFieldValue := mload(add(opts, 0xA0))
            let oldSymbolFieldValue := mload(add(opts, 0xC0))
            mstore(opts, governanceOptsHostsHash)
            mstore(add(opts, 0xA0), nameHash)
            mstore(add(opts, 0xC0), symbolHash)
            h := keccak256(opts, 0xE0)
            mstore(opts, oldGovernanceOptsHostFieldValue)
            mstore(add(opts, 0xA0), oldNameFieldValue)
            mstore(add(opts, 0xC0), oldSymbolFieldValue)
        }
    }

    function _getParty() internal view returns (Party) {
        return party;
    }

    function _getFinalContribution(address contributor)
        internal
        view
        returns (uint256 ethUsed, uint256 ethOwed, uint256 votingPower)
    {
        uint256 totalEthUsed = _getFinalPrice();
        {
            Contribution[] storage contributions = _contributionsByContributor[contributor];
            uint256 numContributions = contributions.length;
            for (uint256 i = 0; i < numContributions; ++i) {
                Contribution memory c = contributions[i];
                if (c.previousTotalContributions >= totalEthUsed) {
                    break;
                }
                if (c.previousTotalContributions + c.amount <= totalEthUsed) {
                    ethUsed += c.amount;
                } else {
                    ethUsed = totalEthUsed - c.previousTotalContributions;
                    ethOwed = c.amount - ethUsed;
                }
            }
        }
        uint256 splitBps_ = uint256(splitBps);
        votingPower = (1e4 - splitBps_) * totalEthUsed / 1e4;
        if (splitRecipient == contributor) {
            // Split recipient is also the contributor so just add the split
            // voting power.
             votingPower += splitBps_ * totalEthUsed / 1e4;
        }
    }

    function _addContribution(
        address contributor,
        uint128 amount,
        address delegate,
        uint128 previousTotalContributions
    )
        internal
    {
        if (delegate == address(0)) {
            revert InvalidDelegateError();
        }
        // Update delegate.
        _delegationsByContributor[contributor] = delegate;
        emit Contributed(contributor, amount, delegate);

        if (amount != 0) {
            // Only allow contributions while the crowdfund is active.
            {
                CrowdfundLifecycle lc = getCrowdfundLifecycle();
                if (lc != CrowdfundLifecycle.Active) {
                    revert WrongLifecycleError(lc);
                }
            }
            // Create contributions entry for this contributor.
            Contribution[] storage contributions = _contributionsByContributor[contributor];
            uint256 numContributions = contributions.length;
            if (numContributions >= 1) {
                Contribution memory lastContribution = contributions[numContributions - 1];
                if (lastContribution.previousTotalContributions == previousTotalContributions) {
                    // No one else has contributed since so just reuse the last entry.
                    lastContribution.amount += amount;
                    contributions[numContributions - 1] = lastContribution;
                    return;
                }
            }
            // Add a new contribution entry.
            contributions.push(Contribution({
                previousTotalContributions: previousTotalContributions,
                amount: amount
            }));
            if (numContributions == 0) {
                // Mint a participation NFT.
                _mint(contributor);
            }
        }
    }

    // Burn the participation NFT for `contributor`, potentially
    // minting voting power and/or refunding unused ETH.
    // `contributor` may also be the split recipient, regardless
    // of whether they are also a contributor or not.
    function _burn(address payable contributor, CrowdfundLifecycle lc, Party party_)
        private
    {
        // If the CF has won, a party must have been created prior.
        if (lc == CrowdfundLifecycle.Won) {
            if (party_ == Party(payable(0))) {
                revert NoPartyError();
            }
        } else {
            // Otherwise it must have lost.
            if (lc != CrowdfundLifecycle.Lost) {
                revert CrowdfundNotOverError(lc);
            }
        }
        if (splitRecipient != contributor || _doesTokenExistFor(contributor)) {
            // Will revert if already burned.
            PartyCrowdfundNFT._burn(contributor);
        }
        (uint256 ethUsed, uint256 ethOwed, uint256 votingPower) =
            _getFinalContribution(contributor);
        if (party_ != Party(payable(0)) && votingPower > 0) {
            _getPartyFactory().mint(
                party_,
                contributor,
                votingPower,
                _delegationsByContributor[contributor] // TODO: Might be 0 for split recipient
            );
        }
        contributor.transferEth(ethOwed);
        emit Burned(contributor, ethUsed, votingPower);
    }

    function _getPartyFactory() private view returns (IPartyFactory) {
        return IPartyFactory(_GLOBALS.getAddress(LibGlobals.GLOBAL_PARTY_FACTORY));
    }

}
