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

## Getting started

First install [Foundry](https://book.getfoundry.sh/getting-started/installation.html).

```
forge install
yarn -D
yarn build
```

## Testing

### Run all tests (except fork tests):

yarn test

### Run only TS tests

yarn test:ts

### Run only Foundry tests

yarn test:sol

### Run forked Foundry tests

forge test -m testFork --fork-url $YOUR_RPC_URL
