# Party Bid V2

The PartyBid V1 protocol allowed people to pool funds together to acquire NFTs. PartyBid V2 adds new features to allow parties to use and govern those NFTs together as well. The party never ends!

## Layout

```
docs/ # Start here
├── overview.md
├── crowdfund.md
└── governance.md
contracts/
│   # Used during the crowdfund phase
├── crowdfund/
│   ├── PartyBid.sol
│   ├── PartyBuy.sol
│   ├── PartyCollectionBuy.sol
│   ├── PartyCrowdfundFactory.sol
│   ├── PartyCrowdfund.sol
│   └── PartyCrowdfundNFT.sol
├── gatekeepers/
│   ├── AllowListGateKeeper.sol
│   └── TokenGateKeeper.sol
├── globals/
│   └── Globals.sol
│   # Used during the governance phase
├── party/
│   ├── Party.sol
│   ├── PartyFactory.sol
│   ├── PartyGovernance.sol
│   └── PartyGovernanceNFT.sol
├── proposals/
│   ├── ProposalExecutionEngine.sol
│   ├── ArbitraryCallsProposal.sol
│   ├── FractionalizeProposal.sol
│   ├── ListOnOpenSeaportProposal.sol
│   └── ListOnZoraProposal.sol
├── distribution/
│   └── TokenDistributor.sol
|   # Used to render crowdfund and governance NFTs
└── renderers/
    ├── PartyCrowdfundNFTRenderer.sol
    └── PartyGovernanceNFTRenderer.sol
sol-tests/ # Foundry tests
tests/ # TS tests
```

## Known Issues / Topics

- It is possible that someone could manipulate parties by contributing ETH and then buying their NFT that they own. This is known and not considered a bug or a valid finding by the team.
- For `PartyBuy` and `PartyCollectionBuy` crowdfunds, the contract allows arbitrary calls via the `buy()` method to buy the NFT and check the NFT is owned by the contract at the end. A potential attack here happens if the crowdfund raises more than the buy price (or if the seller reduces the price). An attacker can then write a contract that when called with the crowdfunds entire ETH balance, buys the NFT for less and sends it to the crowdfund contract, then sends the remaining ETH to the attacker. This behavior exists in V1 as well. In V1, we used an [allow list](https://github.com/PartyDAO/partybid/blob/main/contracts/PartyBuy.sol#L136) to help mitigate. The issue with this is that a motivated actor could still buy the original listing and create a new one on an allowed target then trigger the party to `buy()` that one instead at a higher price, pocketing the difference. We have made peace with this issue and accepted the risk, but the team is open to new solutions.
  - `PartyCollectionBuy` will be much less likely to be affected by this since only a host may call `buy()`.
  - On the frontend, we have thought about nudging contributors whose contribution would push the crowdfund above the buy price to reduce their contribution. We've also considered capping contributions to `maximumPrice`, but we'd prefer to do this on the frontend.
- For `PartyBid` crowdfunds, in the case that a party did not bid at all on the NFT in the auction yet still (somehow) manages to acquire the NFT before `finalize()` is called, all contributions to the crowdfund are considered used so that everyone who contributed wins but no contributions will be refunded back. The ETH contributed would stay in the crowdfund and not be transferred over to the created `Party` instance, effectively burned. The crowdfund could transfer over contributions to the created `Party` to `distribute()` back (refunding it) but this introduces the possibility for someone to make a last minute contribution before `finalize()` is called to boost their voting power at no cost because they could get back all their contributions. This is a rare and atypical enough case that we feel comfortable leaving this behavior alone.
- In `_settleZoraAuction()` in `ListOnZoraProposal`, a try/catch statement is used get the state of an auction. If the `endAuction()` call fails but returns an `"Auction doesn't exit"` we take this as meaning someone else had called `endAuction()` before we did, ending the auction and emitting a `ZoraAuctionSold` event. There is a possibility that a `safeTransferFrom()` call in Zora's `endAuction()` reverts at `onERC721Received()` with a `"Auction doesn't exit"` to trick the party into completing the proposal even though the auction wasn't settled.  However, the party still has the NFT and can just list it elsewhere. This is a known grief and, unless there can be more serious implications, we do not consider it a valid finding.
- If a party were to list a malicious NFT (eg. reverts on transfer after listing), somewhere along the way it may break the proposal flow and put the party in a stuck state until `cancelDelay` is reached. While it is annoying, we do not consider it serious because (1) the proposal can always be canceled and (2) it is unlikely there will be a market for malicious NFTs so the listing is unlikely to go anywhere regardless.

## Getting Started

First install [Foundry](https://book.getfoundry.sh/getting-started/installation.html).

```bash
forge install
yarn -D
yarn build
```

## Testing

### Run all tests (except fork tests):

```bash
yarn test
```

### Run only TS tests

```bash
yarn test:ts
```

### Run only Foundry tests

```bash
yarn test:sol
```

### Run forked Foundry tests

```bash
forge test -m testFork --fork-url $YOUR_RPC_URL
```
