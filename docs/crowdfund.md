# Crowdfund Contracts

These contracts allow people to create and join a crowdfund, pooling ETH together to acquire an NFT. Multiple crowdfund contracts exist for specific acquisition patterns.

## Key Concepts

- **Crowdfunds**: Contracts implementing various strategies that allow people to pool ETH together to acquire an NFT, with the end goal of forming a governance party around it.
- **Crowdfund NFTs**: A _soulbound_ NFT (ERC721) representing contributions made to a crowdfund. Each contributor gets one of these the first time they contribute. At the end of the crowdfund (successful or unsuccessful), these are burned to either redeem unused ETH or mint governance shares.
- **Party**: The governance contract, which will be created and will custody the NFT after it has been acquired by the crowdfund.
- **Globals**: A single contract that holds configuration values, referenced by several ecosystem contracts.
- **Proxies**: All Crowdfund instances are deployed as simple [`Proxy`](../contracts/utils/Proxy.sol) contracts that forward calls to a specific crowdfund implementation that inherits from `PartyCrowdfund`.

## Contracts

The main contracts involved in this phase are:

- `PartyCrowdfundFactory`([source](../contracts/crowdfund/PartyCrowdfundFactory.sol))
  - Factory contract that deploys a new proxified `PartyCrowdfund` instance.
- `PartyCrowdfund` ([source](../contracts/crowdfund/PartyCrowdfund.sol))
  - Abstract base class for all crowdfund contracts. Implements most accounting and end-of-life logic for crowdfunds.
- `PartyBuy` ([source](../contracts/crowdfund/PartyBuy.sol))
  - A crowdfund that purchases a specific NFT (i.e., with known token ID) listing for a known price.
- `PartyCollectionBuy` ([source](../contracts/crowdfund/PartyCollectionBuy.sol))
  - A crowdfund that purchases any NFT from a collection (i.e., any token ID) from a collection for a known price.
- `PartyBid` ([source](../contracts/crowdfund/PartyBid.sol))
  - A crowdfund that can repeatedly bid on an auction for a specific NFT (i.e., with known token ID) until it wins.
- `IMarketWrapper` ([source](../contracts/crowdfund/IMarketWrapper.sol))
  - A generic interface consumed by `PartyBid` to abstract away interactions with any auction marketplace.
- `IGateKeeper` ([source](../contracts/gatekeepers/IGateKeeper.sol))
  - An interface implemented by gatekeeper contracts that restrict who can participate in a crowdfund. There are currently two implementations of this interface:
    - `AllowListGateKeeper` ([source](../contracts/gatekeepers/AllowListGateKeeper.sol))
      - Restricts participation based on whether an address exist in a list.
    - `ERC20TokenGateKeeper` ([source](../contracts/gatekeepers/ERC20TokenGateKeeper.sol))
      - Restricts participation based on whether an address has a minimum balance of an ERC20.
- `Globals` ([code](../contracts/globals/Globals.sol))
  - A contract that defines global configuration values referenced by other contracts across the entire protocol.

![contracts](./crowdfund-contracts.png)

## Crowdfund Creation

Crowdfunds are created through the `PartyCrowdfundFactory`. This will typically be done through the UI when a user starts a party to acquire an NFT.

The sequence of events within the contract are as follows:

1. Call `createPartyBuy`, `createPartyBid`, or `createPartyCollectionBuy` (depending on the [crowdfund type](https://github.com/PartyDAO/partybidV2/blob/main/docs/crowdfund.md#crowdfund-types)) on `PartyCrowdfundFactory` defined as:
   ```solidity
   function createParty<Bid,Buy,CollectionBuy>(
   	PartyBid.Party<Bid,Buy,CollectionBuy>Options memory opts,
   	bytes memory createGateCallData
   )
   ```
   - `opts` are immutable [configuration options](https://github.com/PartyDAO/partybidV2/blob/main/docs/crowdfund.md#crowdfund-options) for the PartyCrowdfund, defining the name and symbol (the PartyCrowdfund instance will also be an ERC721) and parameters used for the initial crowdfund stage and later [governance stage](https://github.com/PartyDAO/partybidV2/blob/main/docs/governance.md) after the crowdfund is successful.
   - `createGateCallData` is an optional parameter that can be passed in to create the gate used by the crowdfund to restrict who can contribute. An existing [gate](https://github.com/PartyDAO/partybidV2/blob/main/docs/crowdfund.md#gatekeepers) can also be used by passing in a valid `opts.gateKeeperId` (in which case `createGateCallData` will be ignored).
   - This will deploy a new `Proxy` instance with an implementation pointing to the PartyCrowdfund contract defined by in the `LibGlobals` contract (eg. `GLOBAL_PARTY_BID_IMPL` for the `PartyBid` implementation).
2. Credit any ETH passed in during deployment or pre-existing to `opts.initialContributor`.
3. At this point, the crowdfund is created and anyone (or anyone allowed by the gatekeeper, if used) can contribute ETH to the party.

## Crowdfund Options

Crowdfunds are initialized with fixed options, i.e. cannot be changed after creating a party. Each crowdfund implementation (`PartyBid`, `PartyBuy`, `PartyCollectionBuy`) defines the options it will need to create its crowdfund. The options that are common across all crowdfunds, most of which are defined by the `PartyCrowdfund.PartyCrowdfundOptions` struct, are the following fields:

- `name`: The name of the party. This will also be used for both the [crowdfund NFT](https://github.com/PartyDAO/partybidV2/blob/main/docs/crowdfund.md#crowdfund-nfts) and the [governance NFT](https://github.com/PartyDAO/partybidV2/blob/main/docs/governance.md#governance-nfts).
- `symbol`: The token symbol of the party. This will be used for both the crowdfund NFT and the governance NFT.
- `nftContract`: The address of the ERC721 contract defining the collection the NFT of interest belongs to.
- `duration`: Duration in seconds that the crowdfund has to acquire the NFT before it expires.
- `maximumBid`/`maximumPrice`: Maximum amount of funds the crowdfund is willing to use to acquire the NFT. A maximum of zero means there is no maximum, unless the crowdfund is a `PartyBid` which must always set a maximum bid amount.
- `splitRecipient`: An address that receives a portion of voting power (or extra voting power) once the party transitions into governance if the crowdfund is successful. Portion received is determined by `splitBps`.
- `splitBps`: Ratio of voting power reserved for the `splitRecipient` in basis points, i.e. `100 = 1%`.
- `initialContributor`: If a crowdfund receives ETH, upon deployment or pre-existing, it will be credited to this address.
- `initialDelegate`: If there is an initial contribution, this is who their voting power will be [delegated](https://github.com/PartyDAO/partybidV2/blob/main/docs/crowdfund.md#delegation) to when the crowdfund transitions to governance.
- `gateKeeper`: The gatekeeper implementation used, if any, to restrict who can contribute to the can contribute to a crowdfund.
- `gateKeeperId`: ID value used to identify the gate used by the crowdfund, if any, within the gatekeeper implementation.
- `governanceOpts`: The [governance options](https://github.com/PartyDAO/partybidV2/blob/main/docs/governance.md#governance-options) that will be set for the party when when it transitions from crowdfund to governance.

## Crowdfund Types

Each crowdfund attempts to acquire one NFT in one collection per PartyCrowdfund instance. There are 3 crowdfund types parties can choose from based on their acquisition strategy:

- [PartyBid](https://github.com/PartyDAO/partybidV2/blob/main/docs/crowdfund.md#partybid)
- [PartyBuy](https://github.com/PartyDAO/partybidV2/blob/main/docs/crowdfund.md#partybuy)
- [PartyCollectionBuy](https://github.com/PartyDAO/partybidV2/blob/main/docs/crowdfund.md#partycollectionbuy)

### PartyBid

This crowdfund type is for raising funds to bid in an auction to acquire a specific NFT. The party can repeated bid on an NFT using funds raised (up to the `maximumBid` amount) until it either acquires the NFT or loses. After the auction, the party will call `PartyBid.finalize()` to finalize the results. If the party won, this will claim the NFT (if necessary) from the market contract hosting the auction and move on to create a governance Party around it. Otherwise if the party lost, the bid will be recovered (if necessary) for contributors to reclaim.

In the case that the party did not bid yet still acquires the NFT in the auction, it will be considered a gift and all contributions towards the crowdfund will be counted such that everyone who contributed wins.

### PartyBuy

This crowdfund type is for raising funds to buy a specific NFT within a specific collection. Anyone in the party can call `PartyBid.buy()` to buy the NFT when the crowdfund has raised enough funds to do so (up to the `maximumPrice`, if set). A governance Party is immediately created afterwards around the newly acquired NFT.

In the case that the purchase was free, all contributions towards it will be counted such that everyone who contributed wins.

### PartyCollectionBuy

This crowdfund type is for raising funds to buy any NFT within a specific collection. It is similar to the `PartyBuy` type, but has some key differences. A `PartyCollectionBuy` crowdfund is not set on which NFT will be bought in the collection. Another difference is that only a party host can call `PartyBid.buy()`. This is because the decision about which NFT in the collection to buy with the party's funds is important and should not be able to be made by just any individual who contributes any amount.

In all other aspects besides the ones mentioned, it functions the same as a `PartyBuy`.

## Crowdfund Lifecycle

The stages of a crowdfund are defined in `PartyCrowdfund.CrowdfundLifecycle`:

- `Invalid`: The crowdfund does not exist.
- `Active`: The crowdfund is currently in progress and accepting contributions.
- `Expired`: The crowdfund has exceeded its duration and expired.
- `Busy`: The crowdfund is in a temporary mid-settlement state, i.e. in the middle of buying an NFT or finalizing an auction. This functions to prevent reentrancy.
- `Lost`: The crowdfund has lost. All contributions will be refunded.
- `Won`: The crowdfund has won. Only unused contributions will be refunded and the party will now transition to the governance stage.

## Contributing

Contributions made towards a crowdfund are all done in ETH. Contributing to a crowdfund is only allowed while the crowdfund is active. Making contributions after the crowdfund has won, lost, or expired will revert.

### Crowdfund NFTs

Upon contributing to a crowdfund, the contributor will receive a crowdfund NFT. This NFT is soulbound, meaning it cannot be transferred or be approved for transfer. Any attempt to do so will revert.

A contributor can only own one crowdfund NFT; multiple contributions by the same contributor will not mint them additional crowdfund NFTs.

After a crowdfund is won and the party transitions to governance, the crowdfund NFT can be burned for a [governance NFT](https://github.com/PartyDAO/partybidV2/blob/main/docs/governance.md#governance-nfts) with voting power equal to their contributions.

Anyone can burn a contributor's crowdfund NFT on their behalf after a successful crowdfund to trigger the minting of their governance NFT. This is to allow their votes to be activated even if the contributor neglects to burn their NFT themselves.

### Accounting

Every contribution made is recorded and stored in an array under the contributor's address.

For each contribution, two details are stored: 1) the `amount` contributed and 2) the `previousTotalContributions` when the contribution was made.

To determine whether a contribution was unused after a crowdfund has concluded, the contract compares the `previousTotalContributions` against the `totalEthUsed` to acquire the NFT.

- If `previousTotalContributions + amount <= totalEthUsed`, then the entire contribution was used.
- If `previousTotalContributions >= totalEthUsed`, then the entire contribution was unused and refunded to the contributor.
- Otherwise, only `totalEthUsed - previousTotalContributions` of the contribution was used and the rest should be refunded to the contributor.

Unused contributions can be reclaimed after the party has either lost or won. For example, if a crowdfund raised 10 ETH to acquired an NFT that was won at 7 ETH, the 3 ETH leftover will be refunded. If the party lost, all 10 ETH will be refunded.

The accounting logic for all this is handled in the `PartyCrowdfund` contract from which all crowdfund types inherit from.

### Delegation

After a successful crowdfund, contributors will gain [voting power](https://github.com/PartyDAO/partybidV2/blob/main/docs/governance.md#voting-power) in Party governance equal to their used contributions.

Upon contributing, users will be able to choose if they want to delegate the voting power they would earn for their contribution in the governance stage to another address or not, maintaining the voting power for themselves.

### Sending ETH

Although it is recommended to make contributions through the `contribute()` method instead of sending ETH to the crowdfund contract, received ETH will still be counted as a contribution credited the sender's address.

If the sender has contributed before and set a delegate, this contribution will also be delegated to the same address.

Note that if the crowdfund is using a gatekeeper that requires calldata to be passed to it (eg. a merkle proof for the [`AllowlistGateKeeper`](https://github.com/PartyDAO/partybidV2/blob/main/docs/crowdfund.md#allowlistgatekeeper)), sending ETH will revert due to the contribution be being blocked by the gatekeeper (`receive()` has not parameters so the calldata used by the gate cannot be passed in).

## Gatekeepers

Gatekeepers allow crowdfunds to limit who can contribute to them. Each gatekeeper implementation stores multiple "gates," i.e. set of conditions used to define whether a participant `isAllowed` to contribute to a crowdfund. Each gate has its own ID.

When a crowdfund is created, users can choose to create a new gate within a gatekeeper implementation or use an existing one by passing in its gate ID. There are currently two gatekeeper types supported:

- [ERC20TokenGateKeeper](https://github.com/PartyDAO/partybidV2/blob/main/docs/crowdfund.md#erc20tokengatekeeper)
- [AllowListGateKeeper](https://github.com/PartyDAO/partybidV2/blob/main/docs/crowdfund.md#allowlistgatekeeper)

### ERC20TokenGateKeeper

This gatekeeper only allows contributions from holders of a specific ERC20 above a specific balance. Each gate stores the ERC20 and minimum balance it requires for participation when the gate is created.

### AllowListGateKeeper

This gatekeeper only allows contributions from addresses on an allowlist. The gatekeeper stores a [merkle root](https://www.investopedia.com/terms/m/merkle-root-cryptocurrency.asp) it uses to check whether an address belongs in the allowlist or not using [proof](https://github.com/Dragonfly-Capital/useful-solidity-patterns/tree/main/examples/merkle-proofs#merkle-proofs-1) provided along with their address. Each gate stores its the merkle root is uses which is set when the gate is created.
