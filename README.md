![Party Protocol](.github/assets/banner.png)

# Party Protocol

A protocol for _group coordination_. Party Protocol provides on-chain functionality for group formation, coordination, and distribution. Currently focused on making NFTs multiplayer.

## Layout

```
docs/ # Start here
├── overview.md
├── crowdfund.md
└── governance.md
contracts/
│   # Used during the crowdfund phase
├── crowdfund/
│   ├── AuctionCrowdfund.sol
│   ├── BuyCrowdfund.sol
│   ├── CollectionBuyCrowdfund.sol
│   ├── CrowdfundFactory.sol
│   ├── Crowdfund.sol
│   └── CrowdfundNFT.sol
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
│   ├── ListOnOpenseaProposal.sol
│   └── ListOnZoraProposal.sol
├── distribution/
│   └── TokenDistributor.sol
|   # Used to render crowdfund and governance NFTs
└── renderers/
    ├── CrowdfundNFTRenderer.sol
    └── PartyNFTRenderer.sol
sol-tests/ # Foundry tests
tests/ # TS tests
```

## Getting started

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
# If you want gas reports:
yarn test:sol --gas-report
```

### Run forked Foundry tests

```bash
forge test -m testFork --fork-url $YOUR_RPC_URL
```

## Audits

The following auditors were engaged to review the protocol before launch:

- a16z Security (no report)
- Code4rena (report [here](./audits/partydao-c4-report.md))
- Macro (report [here](./audits/Party-Protocol-Macro-Audit.pdf))

## License

The primary license for the Party Protocol is the GNU General Public License 3.0 (`GPL-3.0`), see [LICENSE](./LICENSE).

- Several interface/dependencies files from other sources maintain their original license (as indicated in their SPDX header).
- All files in `sol-tests/` and `tests/` remain unlicensed (as indicated in their SPDX header).
