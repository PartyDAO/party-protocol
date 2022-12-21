![Party Protocol](.github/assets/banner.png)

[![Version][version-badge]][version-link]
[![License][license-badge]][license-link]
[![Test][ci-badge]][ci-link]
[![Docs][docs-badge]][docs-link]
[![Discussions][discussions-badge]][discussions-link]
[![Discord][discord-badge]][discord-link]

[version-badge]: https://img.shields.io/github/release/PartyDAO/party-protocol?label=version
[version-link]: https://github.com/PartyDAO/party-protocol/releases
[license-badge]: https://img.shields.io/github/license/PartyDAO/party-protocol
[license-link]: https://github.com/PartyDAO/party-protocol/blob/main/LICENSE
[ci-badge]: https://github.com/PartyDAO/party-protocol/actions/workflows/ci.yml/badge.svg
[ci-link]: https://github.com/PartyDAO/party-protocol/actions/workflows/ci.yml
[docs-badge]: https://img.shields.io/badge/Party-documentation-informational
[docs-link]: https://github.com/PartyDAO/party-protocol/tree/main/docs
[discussions-badge]: https://img.shields.io/badge/Party-discussions-blueviolet
[discussions-link]: https://github.com/PartyDAO/party-protocol/discussions
[discord-badge]: https://img.shields.io/static/v1?logo=discord&label=discord&message=join&color=blue
[discord-link]: https://discord.gg/zUeXpDX8HA

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
  - [Bug Bounty](https://github.com/PartyDAO/party-protocol#bug-bounty)
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
| `CrowdfundFactory`        | [0x1ca2002babed23b91537e2f9c8bb61b97798c806](https://etherscan.io/address/0x1ca2002babed23b91537e2f9c8bb61b97798c806) | [0x1E4887172aE77aC3b426c4e2ACb4E1a0cAC117b0](https://goerli.etherscan.io/address/0x1E4887172aE77aC3b426c4e2ACb4E1a0cAC117b0) |
| `PartyFactory`            | [0x1ca2007d4f2bc0ec2a56ecb890e56e05f36182df](https://etherscan.io/address/0x1ca2007d4f2bc0ec2a56ecb890e56e05f36182df) | [0xc637ee4F7672A0a99B8C6744C2bCC8DcdF8BFaB8](https://goerli.etherscan.io/address/0xc637ee4F7672A0a99B8C6744C2bCC8DcdF8BFaB8) |
| `TokenDistributor`        | [0x1ca2007a81f8a7491bb6e11d8e357fd810896454](https://etherscan.io/address/0x1ca2007a81f8a7491bb6e11d8e357fd810896454) | [0x70487dE2a3c93ABd6B0D23B714437E6376D31A07](https://goerli.etherscan.io/address/0x70487dE2a3c93ABd6B0D23B714437E6376D31A07) |
| `AuctionCrowdfund`        | [0xa23399a573aaf562eec1645096218fecfdc22759](https://etherscan.io/address/0xa23399a573aaf562eec1645096218fecfdc22759) | [0x4734837806f6a2C72fCB8E75e8807961dAa46E04](https://goerli.etherscan.io/address/0x4734837806f6a2C72fCB8E75e8807961dAa46E04) |
| `BuyCrowdfund`            | [0x48ce324bd9ce34217b9c737dda0cec2f28a0626e](https://etherscan.io/address/0x48ce324bd9ce34217b9c737dda0cec2f28a0626e) | [0x6963A71DDdc1eE84Ec6e4F564F05A797b45838Dd](https://goerli.etherscan.io/address/0x6963A71DDdc1eE84Ec6e4F564F05A797b45838Dd) |
| `CollectionBuyCrowdfund`  | [0x57dc04a0270e9f9e6a1289c1559c84098ba0fa9c](https://etherscan.io/address/0x57dc04a0270e9f9e6a1289c1559c84098ba0fa9c) | [0xBa8fa5A71e02910f27688264864D9db8703cf8E9](https://goerli.etherscan.io/address/0xBa8fa5A71e02910f27688264864D9db8703cf8E9) |
| `Party`                   | [0x52010e220e5c8ef2217d86cfa58da51da39e8ec4](https://etherscan.io/address/0x52010e220e5c8ef2217d86cfa58da51da39e8ec4) | [0x23c7A622863f9E14Febab6D8A95018451386e1C3](https://goerli.etherscan.io/address/0x23c7A622863f9E14Febab6D8A95018451386e1C3) |
| `ProposalExecutionEngine` | [0x88d1f63e80a48711d2a458e1924224435c10beed](https://etherscan.io/address/0x88d1f63e80a48711d2a458e1924224435c10beed) | [0x8c741dc23F48DfB3B55b749C8f7a12C620B6022f](https://goerli.etherscan.io/address/0x8c741dc23F48DfB3B55b749C8f7a12C620B6022f) |
| `CrowdfundNFTRenderer`    | [0x565846D035b2B02D6631d579eD34d8f250584015](https://etherscan.io/address/0x565846D035b2B02D6631d579eD34d8f250584015) | [0xA2e5A5F3507408E690fB425DcEE910f506bB6468](https://goerli.etherscan.io/address/0xA2e5A5F3507408E690fB425DcEE910f506bB6468) |
| `PartyNFTRenderer`        | [0xe3211390292300848428640bbc2F324D36a25857](https://etherscan.io/address/0xe3211390292300848428640bbc2F324D36a25857) | [0x3Ea7a966473431fB87d6E8ff4875a164fbEff8FE](https://goerli.etherscan.io/address/0x3Ea7a966473431fB87d6E8ff4875a164fbEff8FE) |
| `RendererStorage`         | [0x9a4fe89316bf81a1e4549476b219c456703c3f62](https://etherscan.io/address/0x9a4fe89316bf81a1e4549476b219c456703c3f62) | [0x16db69EF5650b99Ce6B52F3f004bBbaf503A0687](https://goerli.etherscan.io/address/0x16db69EF5650b99Ce6B52F3f004bBbaf503A0687) |
| `AllowListGatekeeper`     | [0x50c58f8bd97c1845c8e8ff56117dbce8a5b009b2](https://etherscan.io/address/0x50c58f8bd97c1845c8e8ff56117dbce8a5b009b2) | [0xb5DFe70B36e9fb12096e956098e501C078973723](https://goerli.etherscan.io/address/0xb5DFe70B36e9fb12096e956098e501C078973723) |
| `TokenGatekeeper`         | [0x26a7bd6161e4c6ae44620cfc6f7b9c3daf83ad0b](https://etherscan.io/address/0x26a7bd6161e4c6ae44620cfc6f7b9c3daf83ad0b) | [0x7A1613F39E1199468ca95d05Df2eab832BA49F33](https://goerli.etherscan.io/address/0x7A1613F39E1199468ca95d05Df2eab832BA49F33) |
| `Globals`                 | [0x1ca20040ce6ad406bc2a6c89976388829e7fbade](https://etherscan.io/address/0x1ca20040ce6ad406bc2a6c89976388829e7fbade) | [0xeDc4F5241B5Fe67f6d0bF351378af014a67F08d8](https://goerli.etherscan.io/address/0xeDc4F5241B5Fe67f6d0bF351378af014a67F08d8) |
| `FoundationMarketWrapper` | [0x96e5b0519983f2f984324b926e6d28c3a4eb92a1](https://etherscan.io/address/0x96e5b0519983f2f984324b926e6d28c3a4eb92a1) | [0x2675f1e0A0FBA0F64F8FC43733561dAd6dF3214b](https://goerli.etherscan.io/address/0x2675f1e0A0FBA0F64F8FC43733561dAd6dF3214b) |
| `NounsMarketWrapper`      | [0x9319dad8736d752c5c72db229f8e1b280dc80ab1](https://etherscan.io/address/0x9319dad8736d752c5c72db229f8e1b280dc80ab1) | [0x983Da1b9b63051455A5c19D384E52Abd37d96AC4](https://goerli.etherscan.io/address/0x983Da1b9b63051455A5c19D384E52Abd37d96AC4) |
| `ZoraMarketWrapper`       | [0x11c07ce1315a3b92c9755f90cdf40b04b88c5731](https://etherscan.io/address/0x11c07ce1315a3b92c9755f90cdf40b04b88c5731) | [0x64A303E7825eD358E4Cf9A4Af80d1381B52fe333](https://goerli.etherscan.io/address/0x64A303E7825eD358E4Cf9A4Af80d1381B52fe333) |

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

The following are known and are _not_ eligible for a bug bounty:

- Crowdfund host uses their crowdfund's balance to buy their own NFT
- Forcing a `BuyCrowdfund` or `CollectionBuyCrowdfund` to use its entire balance to acquire an NFT above its listed price
- Free or gifted NFTs being locked in a crowdfund after the crowdfund lost

The rubric we use to determine bug bounties is as follows:

| **Level**   | **Example**                                                                                                                                                                                      | **Maximum Bug Bounty** |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------- |
| 6. Severe   | - Draining or freezing of holdings protocol-wide (e.g. draining token distributor, economic attacks, reentrancy, MEV, logic errors)                                                              | Let's talk             |
| 5. Critical | - Contracts with balances can be exploited to steal holdings under specific conditions (e.g. bypass guardrails to transfer precious NFT from parties, user can steal their party's distribution) | Up to 25 ETH           |
| 4. High     | - Contracts temporarily unable to transfer holdings<br>- Users spoof each other                                                                                                                  | Up to 10 ETH           |
| 3. Medium   | - Contract consumes unbounded gas<br>- Griefing, denial of service (i.e. attacker spends as much in gas as damage to the contract)                                                               | Up to 5 ETH            |
| 2. Low      | - Contract fails to behave as expected, but doesn't lose value                                                                                                                                   | Up to 1 ETH            |
| 1. None     | - Best practices                                                                                                                                                                                 |                        |

Any vulnerability or bug discovered must be reported only to the following email: [security@partydao.org](mailto:security@partydao.org).

## License

The primary license for the Party Protocol is the GNU General Public License 3.0 (`GPL-3.0`), see [LICENSE](./LICENSE).

- Several interface/dependencies files from other sources maintain their original license (as indicated in their SPDX header).
- All files in `sol-tests/` and `tests/` remain unlicensed (as indicated in their SPDX header).
