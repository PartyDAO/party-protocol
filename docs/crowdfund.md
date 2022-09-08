# Crowdfund Contracts

These contracts allow people to create and join a crowdfund, pooling ETH together to acquire an NFT. Multiple crowdfund contracts exist for specific acquisition patterns.

---

## Key Concepts

- **Crowdfunds**: Contracts implementing various strategies that allow people to pool ETH together to acquire an NFT, with the end goal of forming a governance party around it.
- **Crowdfund NFTs**: A _soulbound_ NFT (ERC721) representing contributions made to a crowdfund. Each contributor gets one of these the first time they contribute. At the end of the crowdfund (successful or unsuccessful), these are burned to either redeem unused ETH or mint governance shares.
- **Party**: The governance contract, which will be created and will custody the NFT after it has been acquired by the crowdfund.
- **Globals**: A single contract that holds configuration values, referenced by several ecosystem contracts.
- **Proxies**: All Crowdfund instances are deployed as simple [`Proxy`](../contracts/utils/Proxy.sol) contracts that forward calls to a specific crowdfund implementation that inherits from `Crowdfund`.

---

## Contracts

The main contracts involved in this phase are:

- `CrowdfundFactory`([source](../contracts/crowdfund/CrowdfundFactory.sol))
  - Factory contract that deploys a new proxified `Crowdfund` instance.
- `Crowdfund` ([source](../contracts/crowdfund/Crowdfund.sol))
  - Abstract base class for all crowdfund contracts. Implements most contribution accounting and end-of-life logic for crowdfunds.
- `BuyCrowdfund` ([source](../contracts/crowdfund/BuyCrowdfund.sol))
  - A crowdfund that purchases a specific NFT (i.e., with a known token ID) listing for a known price.
- `CollectionBuyCrowdfund` ([source](../contracts/crowdfund/CollectionBuyCrowdfund.sol))
  - A crowdfund that purchases any NFT from a collection (i.e., any token ID) from a collection for a known price. Like `BuyCrowdfund` but allows any token ID in a collection to be bought.
- `AuctionCrowdfund` ([source](../contracts/crowdfund/AuctionCrowdfund.sol))
  - A crowdfund that can repeatedly bid on an auction for a specific NFT (i.e., with a known token ID) until it wins.
- `IMarketWrapper` ([source](../contracts/crowdfund/IMarketWrapper.sol))
  - A generic interface consumed by `AuctionCrowdfund` to abstract away interactions with any auction marketplace.
- `IGateKeeper` ([source](../contracts/gatekeepers/IGateKeeper.sol))
  - An interface implemented by gatekeeper contracts that restrict who can participate in a crowdfund. There are currently two implementations of this interface:
    - `AllowListGateKeeper` ([source](../contracts/gatekeepers/AllowListGateKeeper.sol))
      - Restricts participation based on whether an address exists in a merkle tree.
    - `TokenGateKeeper` ([source](../contracts/gatekeepers/TokenGateKeeper.sol))
      - Restricts participation based on whether an address has a minimum balance of a token (ERC20 or ERC721).
- `Globals` ([code](../contracts/globals/Globals.sol))
  - A contract that defines global configuration values referenced by other contracts across the entire protocol.

![contracts](./crowdfund-contracts.png)

---

## Crowdfund Creation

The `CrowdfundFactory` contract is the canonical contract for creating crowdfund instances. It deploys `Proxy` instances that point to a specific implementation which inherits from `Crowdfund`.

### BuyCrowdfund Crowdfunds

`BuyCrowdfund`s are created via the `createBuyCrowdfund()` function. `BuyCrowdfund`s:

- Are trying to buy a specific ERC721 contract + token ID.
- While active, users can contribute ETH to the cause.
- Succeeds if anyone executes an arbitrary call with value through `buy()` to acquire the NFT.
- Fails if the `expiry` time passes before acquiring the NFT.

#### Crowdfund Specific Creation Options

- `IERC721 nftContract`: The ERC721 contract of the NFT being bought.
- `uint256 nftTokenId`: ID of the NFT being bought.
- `uint40 duration`: How long this crowdfund has to bid on the NFT, in seconds.
- `uint96 maximumPrice`: Maximum amount of ETH this crowdfund will pay for the NFT. If zero, no maximum.

### CollectionBuyCrowdfund Crowdfunds

`CollectionBuyCrowdfund`s are created via the `createCollectionBuyCrowdfund()` function. `CollectionBuyCrowdfund`s:

- Are trying to buy _any_ token ID on an ERC721 contract.
- While active, users can contribute ETH to the cause.
- Succeeds if the host executes an arbitrary call with value through `buy()` to acquire an eligible NFT.
- Fails if the `expiry` time passes before acquiring an eligible NFT.

#### Crowdfund Specific Creation Options

- `IERC721 nftContract`: The ERC721 contract of the NFT being bought.
- `uint40 duration`: How long this crowdfund has to bid on an NFT, in seconds.
- `uint96 maximumPrice`: Maximum amount of ETH this crowdfund will pay for an NFT. If zero, no maximum.

### AuctionCrowdfund Crowdfunds

`CollectionBuyCrowdfund`s are created via the `createAuctionCrowdfund()` function. `AuctionCrowdfund`s:

- Are trying to buy a specific ERC721 contract + token ID listed on an auction market.
- Directly interact with a Market Wrapper, which is an abstractions/wrapper of an NFT auction protocol.
  - These Market Wrappers are inherited from [v1](https://github.com/PartyDAO/PartyBid) of the protocol and are actually delegatecalled into.
- While active, users can contribute ETH to the cause.
- While active, ETH bids can be placed by anyone via the `bid()` function.
- Succeeds if anyone calls `finalize()`, which attempts to settle the auction, and the crowdfund ends up holding the NFT.
- Fails if the `expiry` time passes before acquiring an eligible NFT.

#### Crowdfund Specific Creation Options

- `uint256 auctionId`: The auction ID specific to the `IMarketWrapper` instance being used.
- `IMarketWrapper market`: The auction protocol wrapper contract.
- `IERC721 nftContract`: The ERC721 contract of the NFT being bought.
- `uint256 nftTokenId`: ID of the NFT being bought.
- `uint40 duration`: How long this crowdfund has to bid on the NFT, in seconds.
- `uint96 maximumBid`: Maximum amount of ETH this crowdfund will bid on the NFT.

### Common Creation Options

In addition to the creation options described for each crowdfund type, there are a number of options common to all of them:

- `string name`: The name of the crowdfund/governance party.
- `string symbol`: The token symbol for crowdfund/governance party NFT.
- `address splitRecipient`: An address that receives a portion of voting power (or extra voting power) when the party transitions into governance.
- `uint16 splitBps`: What percentage (in basis points) of the final total voting power `splitRecipient` receives.
- `address initialContributor`: If ETH is attached during deployment, it will be interpreted as a contribution. This is who gets credit for that contribution.
- `address initialDelegate`: If there is an initial contribution, this is who they will initially delegate their voting power to when the crowdfund transitions to governance.
- `IGateKeeper gateKeeper`: The gatekeeper contract to use (if non-null) to restrict who can contribute to this crowdfund.
- `bytes12 gateKeeperId`: The gate ID within the gateKeeper contract to use.
- `FixedGovernanceOpts governanceOpts`: Fixed [governance options](https://github.com/PartyDAO/partybidV2/blob/main/docs/governance.md#governance-options) that the governance Party will be created with if the crowdfund succeeds. Aside from the party `hosts`, only the hash of this field is stored on-chain at creation. It must be provided in full again in order for the party to win.

Crowdfunds are initialized with fixed options, i.e. cannot be changed after creating a party.

### Optional Gatekeeper Creation Data

Each of the mentioned creation functions can also take an optional `bytes createGateCallData` parameter which, if non-empty, will be called against the `gateKeeper` address in each crowdfund's creation options. The intent of this is to call a `createGate()` type function on a gatekeeper instance, so users can deploy a new crowdfund with a new gate in the same transaction. This function call is expected to return a `bytes12`, which will be decoded and will overwrite the `gateKeeperId` in the crowdfund's creation options. Neither the `createGateCallData` nor `gateKeeper` are scrutinized since the factory has no other responsibilities, privileges, or assets.

### Optional Initial Contribution

All creation functions are `payable`. Any ETH attached to the call will be attached to the deployment of the crowdfund's `Proxy`. This will be detected in the `Crowdfund` constructor and treated as an initial contribution to the crowdfund. The party's `initialContributor` option will designate who to credit for this contribution.

## Crowdfund Lifecycle

All crowdfunds share a concept of a lifecycle, wherein only certain actions can be performed. These are defined in `Crowdfund.CrowdfundLifecycle`:

- `Invalid`: The crowdfund does not exist.
- `Active`: The crowdfund has been created and contributions can be made and acquisition functions may be called.
- `Expired`: The crowdfund has passed its expiration time. No more contributions are allowed.
- `Busy`: An temporary state set by the contract during complex operations to act as a reentrancy guard.
- `Lost`: The crowdfund has failed to acquire the NFT in time. Contributors can reclaim their full contributions.
- `Won`: The crowdfund has acquired the NFT and it is now held by a governance party. Contributors can claim their voting tokens.

## Making Contributions

While the crowdfund is in the `Active` lifecycle, users can contribute ETH to it.

The only way of contributing to a crowdfund is through the payable `contribute()` function. Contribution records are created per-user, tracking the individual contribution amount as well as the overall total contribution amount, in order to determine what fraction of each user's contribution was used by a successful crowdfund.

### Participation NFTs

The first time a user contributes, they are minted a soulbound participation NFT, which is implemented by the crowdfund contract itself. This NFT can later be burned to refund unused ETH and/or mint voting power in the governance party.

A contributor can only own one crowdfund NFT; multiple contributions by the same contributor will not mint them additional crowdfund NFTs.

### Accounting

Every contribution made is recorded and stored in an array under the contributor's address.

For each contribution, two details are stored: 1) the `amount` contributed and 2) the `previousTotalContributions` when the contribution was made.

To determine whether a contribution was unused after a crowdfund has concluded, the contract compares the `previousTotalContributions` against the `totalEthUsed` to acquire the NFT.

- If `previousTotalContributions + amount <= totalEthUsed`, then the entire contribution was used.
- If `previousTotalContributions >= totalEthUsed`, then the entire contribution was unused and refunded to the contributor.
- Otherwise, only `totalEthUsed - previousTotalContributions` of the contribution was used and the rest should be refunded to the contributor.

Unused contributions can be reclaimed after the party has either lost or won. For example, if a crowdfund raised 10 ETH to acquire an NFT that was won at 7 ETH, the 3 ETH leftover will be refunded. If the party lost, all 10 ETH will be refunded.

The accounting logic for all this is handled in the `Crowdfund` contract from which all crowdfund types inherit from.

### Extra Parameters

The `contribute()` function accepts a delegate parameter, which will be the user's initial delegate when they mint their voting power in the governance party. Future contributions (even 0-value contributions) can change the initial delegate. It is valid to call `contribute()` with `0` value even after the crowdfund expires or ends in order to update a user's chosen delegate.

The `contribute()` function accepts a `gateData` parameter, which will be passed to the gatekeeper a party has chosen (if any). If there is a gatekeeper in use, this arbitrary data must be used by the gatekeeper to prove that the contributor is allowed to participate.

## Winning

Each crowdfund type has its own criteria and operations for winning.

### BuyCrowdfund

`BuyCrowdfund` wins if _anyone_ successfully calls `buy()` before the crowdfund expires. The `buy()` function will perform an arbitrary call with value (up to `maximumPrice`) to attempt to acquire the predetermined NFT. The NFT must be held by the party after the arbitrary call successfully returns. It will then proceed with creating a governance Party.

### CollectionBuyCrowdfund

`CollectionBuyCrowdfund` wins if a _host_ successfully calls `buy()` before the crowdfund expires. The `buy()` function will perform an arbitrary call with value (up to `maximumPrice`) to attempt to acquire _any_ NFT token ID from the predetermined ERC721. The NFT must be held by the party after the arbitrary call successfully returns. It will then proceed with creating a governance Party.

### AuctionCrowdfund

`AuctionCrowdfund` requires more steps and active intervention than the other crowdfunds because it needs to interact with auctions.

While the crowdfund is Active, anyone can, and should, call `bid()` to bid on the auction the crowdfund was started around. The amount to bid will be the minimum winning amount determined by the Market Wrapper being used. Only up to `maximumBid` ETH will ever be used in a bid. The crowdfund contract will `delegatecall` into the Market Wrapper to perform the bid, so it is important that a crowdfund only uses trusted Market Wrappers.

After the auction has ended, someone must call `finalize()`, regardless of whether the crowdfund has placed a bid or not. This will settle the auction (if necessary), possibly returning bidded ETH to the party or acquiring the auctioned NFT. It is possible to call `finalize()` even after the crowdfund has Expired and the crowdfund may even still win in this scenario. If the NFT was acquired, it will then proceed with creating a governance party.

### Creating a Governance Party

In every crowdfund, immediately after the party has won by acquiring the NFT, it will create a new governance Party instance, using the same fixed governance options provided at crowdfund creation. The `totalVotingPower` the governance Party is created with is simply the settled price of the NFT (how much ETH we paid for it). The bought NFT is immediately transferred to the governance Party as well.

After this point, the crowdfund will be in the `Won` lifecycle and no more contributions will be allowed. Contributors can `burn()` their participation NFT to refund any ETH they contributed that was not used as well as mint voting power within the governance Party (which is also an NFT).

## Losing

Crowdfunds generally lose when they expire before acquiring a target NFT. The one exception is `AuctionCrowdfund`, which can still be finalized and win after expiration.

When a crowdfund enters the Lost lifecycle, contributors may `burn()` their participation NFT to refund all the ETH they contributed.

## Burning

At the conclusion of a crowdfund (Won or Lost lifecycle), contributors may burn their participation NFT via the `burn()` function.

If the crowdfund lost, burning the participation NFT will refund all of the contributor's contributed ETH.
If the crowdfund won, burning the participation NFT will refund any of the contributor's _unused_ ETH and mint voting power in the governance party.

### Calculating Voting Power

Voting power for a contributor is equivalent to the amount of ETH they contributed that was used to acquire the NFT. Each individual contribution is tracked against the total ETH raised at the time of contribution. If a user contributes after the crowdfund received enough ETH to acquire the NFT, only their contributions from prior will count towards their final voting power. All else will be refunded when they burn their participation token.

- If the crowdfund was created with a valid `splitBps` value, this percent of every contributor's voting power will be reserved for the `splitRecipient` to claim. If they are also a contributor, they will receive the sum of both.

### Burning Someone Else's NFT

It's not uncommon for contributors to go inactive before a crowdfund ends. To help ensure delegates in the governance party have enough voting power to operate in proposal flow as quickly as possible, anyone can burn any contributor's participation NFT. This will credit a contributor's delegate in the governance Party with that contributor's voting power, which may be enough to act on proposals without the contributor's intervention.

## Gatekeepers

Gatekeepers allow crowdfunds to limit who can contribute to them. Each gatekeeper implementation stores multiple "gates," i.e. a set of conditions used to define whether a participant `isAllowed` to contribute to a crowdfund. Each gate has its own ID.

When a crowdfund is created, users can choose to create a new gate within a gatekeeper implementation or use an existing one by passing in its gate ID. There are currently two gatekeeper types supported:

- [TokenGateKeeper](https://github.com/PartyDAO/partybidV2/blob/main/docs/crowdfund.md#tokengatekeeper)
- [AllowListGateKeeper](https://github.com/PartyDAO/partybidV2/blob/main/docs/crowdfund.md#allowlistgatekeeper)

### TokenGateKeeper

This gatekeeper only allows contributions from holders of a specific token (e.g. ERC20 or ERC721) above a specific balance. Each gate stores the token and minimum balance it requires for participation when the gate is created. While ERC20 and ERC721 tokens will be the predominant usecase, any contract that implements `balanceOf()` can be used to gate.

### AllowListGateKeeper

This gatekeeper only allows contributions from addresses on an allowlist. The gatekeeper stores a [merkle root](https://www.investopedia.com/terms/m/merkle-root-cryptocurrency.asp) it uses to check whether an address belongs in the allowlist or not using [proof](https://github.com/dragonfly-xyz/useful-solidity-patterns/tree/main/examples/merkle-proofs#merkle-proofs-1) provided along with their address. Each gate stores the merkle root it uses which is set when the gate is created.
