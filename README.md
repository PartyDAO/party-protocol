![Party Protocol](.github/assets/banner.png)

# Party Protocol

A protocol for _group coordination_. Party Protocol provides on-chain functionality for group formation, coordination, and distribution. Currently focused on making NFTs multiplayer.

## Table of Contents

- [Party Protocol](https://github.com/PartyDAO/party-protocol#party-protocol)
  - [Table of Contents](https://github.com/PartyDAO/party-protocol#table-of-contents)
  - [Documentation](https://github.com/PartyDAO/party-protocol#documentation)
  - [Contributing](https://github.com/PartyDAO/party-protocol#contributing)
  - [Layout](https://github.com/PartyDAO/party-protocol#layout)
  - [Deployments](https://github.com/PartyDAO/party-protocol#deployments)
  - [Install](https://github.com/PartyDAO/party-protocol#install)
  - [Testing](https://github.com/PartyDAO/party-protocol#testing)
  - [Audits](https://github.com/PartyDAO/party-protocol#audits)
  - [License](https://github.com/PartyDAO/party-protocol#license)

## Documentation

For more information on Party Protocol, see the documentation [here](./docs/).

- [Overview](./docs/README.md)
- [Crowdfund](./docs/crowdfund.md)
- [Governance](./docs/governance.md)

## Contributing

This is an open protocol, so if you are interested in contributioning see [here](./CONTRIBUTING.md) for more details about how you could get involved.

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

## Deployments

| Contract                  | Ethereum                                                                                                              | Goerli                                                                                                                       |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `CrowdfundFactory`        | [0x1ca2002babed23b91537e2f9c8bb61b97798c806](https://etherscan.io/address/0x1ca2002babed23b91537e2f9c8bb61b97798c806) | [0xe84a62494aaaa4090a561dec1561cb10a93a93ab](https://goerli.etherscan.io/address/0xe84a62494aaaa4090a561dec1561cb10a93a93ab) |
| `PartyFactory`            | [0x1ca2007d4f2bc0ec2a56ecb890e56e05f36182df](https://etherscan.io/address/0x1ca2007d4f2bc0ec2a56ecb890e56e05f36182df) | [0xd1bc5eed9a90911caa76a8ea1f11c4ea012976fc](https://goerli.etherscan.io/address/0xd1bc5eed9a90911caa76a8ea1f11c4ea012976fc) |
| `TokenDistributor`        | [0x1ca2007a81f8a7491bb6e11d8e357fd810896454](https://etherscan.io/address/0x1ca2007a81f8a7491bb6e11d8e357fd810896454) | [0xe6f58b31344404e3479d81fb8f9dd592feb37965](https://goerli.etherscan.io/address/0xe6f58b31344404e3479d81fb8f9dd592feb37965) |
| `AuctionCrowdfund`        | [0xa23399a573aaf562eec1645096218fecfdc22759](https://etherscan.io/address/0xa23399a573aaf562eec1645096218fecfdc22759) | [0xe0a0fcc467196fda0a6cbdbba73505aed1e31b31](https://goerli.etherscan.io/address/0xe0a0fcc467196fda0a6cbdbba73505aed1e31b31) |
| `BuyCrowdfund`            | [0x48ce324bd9ce34217b9c737dda0cec2f28a0626e](https://etherscan.io/address/0x48ce324bd9ce34217b9c737dda0cec2f28a0626e) | [0x1471fe2985810525f29412dc555c5a911403d144](https://goerli.etherscan.io/address/0x1471fe2985810525f29412dc555c5a911403d144) |
| `CollectionBuyCrowdfund`  | [0x57dc04a0270e9f9e6a1289c1559c84098ba0fa9c](https://etherscan.io/address/0x57dc04a0270e9f9e6a1289c1559c84098ba0fa9c) | [0x0d5a70d1a340c737b74162a60ffca0f94a4c9699](https://goerli.etherscan.io/address/0x0d5a70d1a340c737b74162a60ffca0f94a4c9699) |
| `Party`                   | [0x52010e220e5c8ef2217d86cfa58da51da39e8ec4](https://etherscan.io/address/0x52010e220e5c8ef2217d86cfa58da51da39e8ec4) | [0xa3b4a7110b48fdff1970d787d1cdcb9679176464](https://goerli.etherscan.io/address/0xa3b4a7110b48fdff1970d787d1cdcb9679176464) |
| `ProposalExecutionEngine` | [0x88d1f63e80a48711d2a458e1924224435c10beed](https://etherscan.io/address/0x88d1f63e80a48711d2a458e1924224435c10beed) | [0xd36689563949ddf6ff01d89b514f6bfc2b443dde](https://goerli.etherscan.io/address/0xd36689563949ddf6ff01d89b514f6bfc2b443dde) |
| `CrowdfundNFTRenderer`    | [0x696dd1e15991969d5629d446d24dc2df9830e419](https://etherscan.io/address/0x696dd1e15991969d5629d446d24dc2df9830e419) | [0xe99446935bc7ef76f68cb0250f0e3e1c72371fb4](https://goerli.etherscan.io/address/0xe99446935bc7ef76f68cb0250f0e3e1c72371fb4) |
| `PartyNFTRenderer`        | [0x7826f0b923e4ba1b9412c8adf4cf19c87146d2d3](https://etherscan.io/address/0x7826f0b923e4ba1b9412c8adf4cf19c87146d2d3) | [0xeef9cd7a71d31054f794545308cf0503708b2980](https://goerli.etherscan.io/address/0xeef9cd7a71d31054f794545308cf0503708b2980) |
| `RendererStorage`         | [0x9a4fe89316bf81a1e4549476b219c456703c3f62](https://etherscan.io/address/0x9a4fe89316bf81a1e4549476b219c456703c3f62) | [0x35c3bd81f7b3e2ddce70f2b9f2ca94ac9992ee23](https://goerli.etherscan.io/address/0x35c3bd81f7b3e2ddce70f2b9f2ca94ac9992ee23) |
| `AllowListGatekeeper`     | [0x50c58f8bd97c1845c8e8ff56117dbce8a5b009b2](https://etherscan.io/address/0x50c58f8bd97c1845c8e8ff56117dbce8a5b009b2) | [0xadcec7b4db7969dff00b9e5304be8e0d1261d6b4](https://goerli.etherscan.io/address/0xadcec7b4db7969dff00b9e5304be8e0d1261d6b4) |
| `TokenGatekeeper`         | [0x26a7bd6161e4c6ae44620cfc6f7b9c3daf83ad0b](https://etherscan.io/address/0x26a7bd6161e4c6ae44620cfc6f7b9c3daf83ad0b) | [0xa6fbce9898a34a1e6db5dab699b20b6bfefda8c3](https://goerli.etherscan.io/address/0xa6fbce9898a34a1e6db5dab699b20b6bfefda8c3) |
| `Globals`                 | [0x1ca20040ce6ad406bc2a6c89976388829e7fbade](https://etherscan.io/address/0x1ca20040ce6ad406bc2a6c89976388829e7fbade) | [0x753e22d4e112a4d8b07df9c4c578b116e3b48792](https://goerli.etherscan.io/address/0x753e22d4e112a4d8b07df9c4c578b116e3b48792) |
| `FoundationMarketWrapper` | [0x96e5b0519983f2f984324b926e6d28c3a4eb92a1](https://etherscan.io/address/0x96e5b0519983f2f984324b926e6d28c3a4eb92a1) | [0xc1bb865106e3c86b1804ffaac7795f82c93c8cef](https://goerli.etherscan.io/address/0xc1bb865106e3c86b1804ffaac7795f82c93c8cef) |
| `NounsMarketWrapper`      | [0x9319dad8736d752c5c72db229f8e1b280dc80ab1](https://etherscan.io/address/0x9319dad8736d752c5c72db229f8e1b280dc80ab1) | [0x8633b1f69da83067ab1ec85a3411de354fbf96cd](https://goerli.etherscan.io/address/0x8633b1f69da83067ab1ec85a3411de354fbf96cd) |
| `ZoraMarketWrapper`       | [0x11c07ce1315a3b92c9755f90cdf40b04b88c5731](https://etherscan.io/address/0x11c07ce1315a3b92c9755f90cdf40b04b88c5731) | [0x969ee9ea5cebc042b689bff8e5497f96808353ae](https://goerli.etherscan.io/address/0x969ee9ea5cebc042b689bff8e5497f96808353ae) |

## Install

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

### Run only TypeScript tests

```bash
yarn test:ts
```

### Run only Foundry tests

```bash
yarn test:sol
# If you want gas reports:
yarn test:sol --gas-report
```

### Run Foundry forked tests

```bash
forge test -m testFork --fork-url $YOUR_RPC_URL
```

## Audits

The following auditors were engaged to review the protocol before launch:

- Code4rena (report [here](./audits/partydao-c4-report.md))
- Macro (report [here](./audits/Party-Protocol-Macro-Audit.pdf))

## Bug Bounty

All contracts except tests, interfaces, dependencies, and those in `renderers/` are in scope and eligible for the Party Protocol Bug Bounty program.

The rubric we use to determine bug bounties is as follows:

| **Level**   | **Example**                                                                                                                                                                                      | **Maximum Bug Bounty** |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------- |
| 6. Severe   | - Draining or freezing of holdings protocol-wide (e.g. draining token distributor, economic attacks, flash loan attacks, reentrancy, MEV, logic errors)                                          | Let's talk             |
| 5. Critical | - Contracts with balances can be exploited to steal holdings under specific conditions (e.g. bypass guardrails to transfer precious NFT from parties, user can steal their party's distribution) | Up to 25 ETH           |
| 4. High     | - Contracts temporarily unable to transfer holdings<br>- Users spoof each other                                                                                                                  | Up to 10 ETH           |
| 3. Medium   | - Contract consumes unbounded gas<br>- Griefing, denial of service (i.e. attacker spends as much in gas as damage to the contract)                                                               | Up to 5 ETH            |
| 2. Low      | - Contract fails to deliver promised returns, but doesn't lose value                                                                                                                             | Up to 1 ETH            |
| 1. None     | - Best practices                                                                                                                                                                                 |                        |

Any vulnerability or bug discovered must be reported only to the following email: [security@partydao.org](mailto:security@partydao.org).

## License

The primary license for the Party Protocol is the GNU General Public License 3.0 (`GPL-3.0`), see [LICENSE](./LICENSE).

- Several interface/dependencies files from other sources maintain their original license (as indicated in their SPDX header).
- All files in `sol-tests/` and `tests/` remain unlicensed (as indicated in their SPDX header).
