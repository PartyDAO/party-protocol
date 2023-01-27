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
| `CrowdfundFactory`        | [0x1ca2002babed23b91537e2f9c8bb61b97798c806](https://etherscan.io/address/0x1ca2002babed23b91537e2f9c8bb61b97798c806) | [0x6B7ac56399eC194DaEa95516086a9e7a58D13e01](https://goerli.etherscan.io/address/0x6B7ac56399eC194DaEa95516086a9e7a58D13e01) |
| `PartyFactory`            | [0x1ca2007d4f2bc0ec2a56ecb890e56e05f36182df](https://etherscan.io/address/0x1ca2007d4f2bc0ec2a56ecb890e56e05f36182df) | [0x1F0518a7E0C0caE9C76BEc1E35d5EB6A80376782](https://goerli.etherscan.io/address/0x1F0518a7E0C0caE9C76BEc1E35d5EB6A80376782) |
| `TokenDistributor`        | [0x1ca2007a81f8a7491bb6e11d8e357fd810896454](https://etherscan.io/address/0x1ca2007a81f8a7491bb6e11d8e357fd810896454) | [0xe1F79b1eaF8f5f57ba884832562Fa600AA99E60a](https://goerli.etherscan.io/address/0xe1F79b1eaF8f5f57ba884832562Fa600AA99E60a) |
| `AuctionCrowdfund`        | [0x2140731a4fdc2531f5138635e457d468c8f4210b](https://etherscan.io/address/0x2140731a4fdc2531f5138635e457d468c8f4210b) | [0x8ecc9771e73D19E2A7C0EF70f4e6752aa868f69D](https://goerli.etherscan.io/address/0x8ecc9771e73D19E2A7C0EF70f4e6752aa868f69D) |
| `BuyCrowdfund`            | [0x569d98c73d7203d6d587d0f355b66bfa258d736f](https://etherscan.io/address/0x569d98c73d7203d6d587d0f355b66bfa258d736f) | [0x5AB7914453edf56d31362905f9B03Bb64739E910](https://goerli.etherscan.io/address/0x5AB7914453edf56d31362905f9B03Bb64739E910) |
| `CollectionBuyCrowdfund`  | [0x43844369a7a6e83b6da64b9b3121b4b66d71cad0](https://etherscan.io/address/0x43844369a7a6e83b6da64b9b3121b4b66d71cad0) | [0x81789d03Dc069ee81e4073C8F7E0110716C7057b](https://goerli.etherscan.io/address/0x81789d03Dc069ee81e4073C8F7E0110716C7057b) |
| `Party`                   | [0x52010e220e5c8ef2217d86cfa58da51da39e8ec4](https://etherscan.io/address/0x52010e220e5c8ef2217d86cfa58da51da39e8ec4) | [0x6A65e9D0052324f0f1396F3395AC8cD592cc1025](https://goerli.etherscan.io/address/0x6A65e9D0052324f0f1396F3395AC8cD592cc1025) |
| `ProposalExecutionEngine` | [0xa51eF92Ee7F24EFf05f5E5CC2119C22C4F8843F6](https://etherscan.io/address/0xa51eF92Ee7F24EFf05f5E5CC2119C22C4F8843F6) | [0xadB962A081efaaf26Bd6fB37F517FF96026b9F2f](https://goerli.etherscan.io/address/0xadB962A081efaaf26Bd6fB37F517FF96026b9F2f) |
| `CrowdfundNFTRenderer`    | [0x565846D035b2B02D6631d579eD34d8f250584015](https://etherscan.io/address/0x565846D035b2B02D6631d579eD34d8f250584015) | [0xc63683758e1ea09f4e26054565C426BDF7f9839c](https://goerli.etherscan.io/address/0xc63683758e1ea09f4e26054565C426BDF7f9839c) |
| `PartyNFTRenderer`        | [0xe3211390292300848428640bbc2F324D36a25857](https://etherscan.io/address/0xe3211390292300848428640bbc2F324D36a25857) | [0x7cb6CBDc28E67444A5bAe8e51Ced8886F36B90ae](https://goerli.etherscan.io/address/0x7cb6CBDc28E67444A5bAe8e51Ced8886F36B90ae) |
| `RendererStorage`         | [0x9a4fe89316bf81a1e4549476b219c456703c3f62](https://etherscan.io/address/0x9a4fe89316bf81a1e4549476b219c456703c3f62) | [0x444D88e3A4947006FFdee3cdc853617212e27878](https://goerli.etherscan.io/address/0x444D88e3A4947006FFdee3cdc853617212e27878) |
| `AllowListGatekeeper`     | [0x50c58f8bd97c1845c8e8ff56117dbce8a5b009b2](https://etherscan.io/address/0x50c58f8bd97c1845c8e8ff56117dbce8a5b009b2) | [0xbC7d1A260B4d65D2170bd2f56fe1dF394CBaa851](https://goerli.etherscan.io/address/0xbC7d1A260B4d65D2170bd2f56fe1dF394CBaa851) |
| `TokenGatekeeper`         | [0x26a7bd6161e4c6ae44620cfc6f7b9c3daf83ad0b](https://etherscan.io/address/0x26a7bd6161e4c6ae44620cfc6f7b9c3daf83ad0b) | [0x62aE80f153f339f07b287Ac925cAA59afe088252](https://goerli.etherscan.io/address/0x62aE80f153f339f07b287Ac925cAA59afe088252) |
| `Globals`                 | [0x1ca20040ce6ad406bc2a6c89976388829e7fbade](https://etherscan.io/address/0x1ca20040ce6ad406bc2a6c89976388829e7fbade) | [0xb04e111BAf8A256ec5Eeafb006d9073301C2831b](https://goerli.etherscan.io/address/0xb04e111BAf8A256ec5Eeafb006d9073301C2831b) |
| `FoundationMarketWrapper` | [0x96e5b0519983f2f984324b926e6d28c3a4eb92a1](https://etherscan.io/address/0x96e5b0519983f2f984324b926e6d28c3a4eb92a1) | [0x07E280f3f018c4f3B88Ba2a80EC237e580da4bE3](https://goerli.etherscan.io/address/0x07E280f3f018c4f3B88Ba2a80EC237e580da4bE3) |
| `NounsMarketWrapper`      | [0x9319dad8736d752c5c72db229f8e1b280dc80ab1](https://etherscan.io/address/0x9319dad8736d752c5c72db229f8e1b280dc80ab1) | [0xf33eCdf1dC52279eE1E4E9b47857041F97bf1830](https://goerli.etherscan.io/address/0xf33eCdf1dC52279eE1E4E9b47857041F97bf1830) |
| `ZoraMarketWrapper`       | [0x11c07ce1315a3b92c9755f90cdf40b04b88c5731](https://etherscan.io/address/0x11c07ce1315a3b92c9755f90cdf40b04b88c5731) | [0xdaB9D7D0363EE75b7D41543624FfE3eCb6815aFB](https://goerli.etherscan.io/address/0xdaB9D7D0363EE75b7D41543624FfE3eCb6815aFB) |

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
