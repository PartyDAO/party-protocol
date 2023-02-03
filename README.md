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
| `CrowdfundFactory`        | [0x1ca2002babed23b91537e2f9c8bb61b97798c806](https://etherscan.io/address/0x1ca2002babed23b91537e2f9c8bb61b97798c806) | [0xCFe71B22Ad978833E10E24b7eEE3519cFdeA0fCF](https://goerli.etherscan.io/address/0xCFe71B22Ad978833E10E24b7eEE3519cFdeA0fCF) |
| `PartyFactory`            | [0x1ca2007d4f2bc0ec2a56ecb890e56e05f36182df](https://etherscan.io/address/0x1ca2007d4f2bc0ec2a56ecb890e56e05f36182df) | [0x00226e624073C39e8176B57eA5DD252d41684C2b](https://goerli.etherscan.io/address/0x00226e624073C39e8176B57eA5DD252d41684C2b) |
| `TokenDistributor`        | [0x1ca2007a81f8a7491bb6e11d8e357fd810896454](https://etherscan.io/address/0x1ca2007a81f8a7491bb6e11d8e357fd810896454) | [0x3A3DAeA15919a5B53B74BD39aa2c0b224a4114EB](https://goerli.etherscan.io/address/0x3A3DAeA15919a5B53B74BD39aa2c0b224a4114EB) |
| `AuctionCrowdfund`        | [0x2140731a4fdc2531f5138635e457d468c8f4210b](https://etherscan.io/address/0x2140731a4fdc2531f5138635e457d468c8f4210b) | [0x1828A0BF94b2E14Ba960300A533736B35be371A6](https://goerli.etherscan.io/address/0x1828A0BF94b2E14Ba960300A533736B35be371A6) |
| `BuyCrowdfund`            | [0x569d98c73d7203d6d587d0f355b66bfa258d736f](https://etherscan.io/address/0x569d98c73d7203d6d587d0f355b66bfa258d736f) | [0x1EAdea6b3383388b0F35f96720157606a71117b7](https://goerli.etherscan.io/address/0x1EAdea6b3383388b0F35f96720157606a71117b7) |
| `CollectionBuyCrowdfund`  | [0x43844369a7a6e83b6da64b9b3121b4b66d71cad0](https://etherscan.io/address/0x43844369a7a6e83b6da64b9b3121b4b66d71cad0) | [0x3907e1b7112D7C672C361aCf9ACA2513b65f8590](https://goerli.etherscan.io/address/0x3907e1b7112D7C672C361aCf9ACA2513b65f8590) |
| `Party`                   | [0x52010e220e5c8ef2217d86cfa58da51da39e8ec4](https://etherscan.io/address/0x52010e220e5c8ef2217d86cfa58da51da39e8ec4) | [0x3AbC024F01A47C9a891BcE8fA8f507bca13c05cf](https://goerli.etherscan.io/address/0x3AbC024F01A47C9a891BcE8fA8f507bca13c05cf) |
| `ProposalExecutionEngine` | [0xa51eF92Ee7F24EFf05f5E5CC2119C22C4F8843F6](https://etherscan.io/address/0xa51eF92Ee7F24EFf05f5E5CC2119C22C4F8843F6) | [0x343B363EaCBfb3955B8C545Cb2c1680A7aA298DE](https://goerli.etherscan.io/address/0x343B363EaCBfb3955B8C545Cb2c1680A7aA298DE) |
| `CrowdfundNFTRenderer`    | [0x565846D035b2B02D6631d579eD34d8f250584015](https://etherscan.io/address/0x565846D035b2B02D6631d579eD34d8f250584015) | [0xCe343eE1147C7c97Db54874f81bcC9Cbc5C7E447](https://goerli.etherscan.io/address/0xCe343eE1147C7c97Db54874f81bcC9Cbc5C7E447) |
| `PartyNFTRenderer`        | [0xe3211390292300848428640bbc2F324D36a25857](https://etherscan.io/address/0xe3211390292300848428640bbc2F324D36a25857) | [0xA6D1b0E378eE54d1FD8C642721234d48b6f68008](https://goerli.etherscan.io/address/0xA6D1b0E378eE54d1FD8C642721234d48b6f68008) |
| `RendererStorage`         | [0x9a4fe89316bf81a1e4549476b219c456703c3f62](https://etherscan.io/address/0x9a4fe89316bf81a1e4549476b219c456703c3f62) | [0x1a347E3d892Ebf8af942380AA65C0708834840a1](https://goerli.etherscan.io/address/0x1a347E3d892Ebf8af942380AA65C0708834840a1) |
| `AllowListGatekeeper`     | [0x50c58f8bd97c1845c8e8ff56117dbce8a5b009b2](https://etherscan.io/address/0x50c58f8bd97c1845c8e8ff56117dbce8a5b009b2) | [0x39e51ebEF008A0Db4b266D071BeaF6e576C4e656](https://goerli.etherscan.io/address/0x39e51ebEF008A0Db4b266D071BeaF6e576C4e656) |
| `TokenGatekeeper`         | [0x26a7bd6161e4c6ae44620cfc6f7b9c3daf83ad0b](https://etherscan.io/address/0x26a7bd6161e4c6ae44620cfc6f7b9c3daf83ad0b) | [0x9175A8077eD8D12A0821Fa03260eD05e1345712a](https://goerli.etherscan.io/address/0x9175A8077eD8D12A0821Fa03260eD05e1345712a) |
| `Globals`                 | [0x1ca20040ce6ad406bc2a6c89976388829e7fbade](https://etherscan.io/address/0x1ca20040ce6ad406bc2a6c89976388829e7fbade) | [0xc01593F2A936C3E132b80d8E91cf12244b2E8A8b](https://goerli.etherscan.io/address/0xc01593F2A936C3E132b80d8E91cf12244b2E8A8b) |
| `FoundationMarketWrapper` | [0x96e5b0519983f2f984324b926e6d28c3a4eb92a1](https://etherscan.io/address/0x96e5b0519983f2f984324b926e6d28c3a4eb92a1) | [0x8959772E781208A1Cb0CB8FBD0089B411a52FA62](https://goerli.etherscan.io/address/0x8959772E781208A1Cb0CB8FBD0089B411a52FA62) |
| `NounsMarketWrapper`      | [0x9319dad8736d752c5c72db229f8e1b280dc80ab1](https://etherscan.io/address/0x9319dad8736d752c5c72db229f8e1b280dc80ab1) | [0x694A5004432D2502780d4338165761a0B35aD690](https://goerli.etherscan.io/address/0x694A5004432D2502780d4338165761a0B35aD690) |
| `ZoraMarketWrapper`       | [0x11c07ce1315a3b92c9755f90cdf40b04b88c5731](https://etherscan.io/address/0x11c07ce1315a3b92c9755f90cdf40b04b88c5731) | [0x80c4ccD109c68Fe36a8F9Cf47c347208E6B5D333](https://goerli.etherscan.io/address/0x80c4ccD109c68Fe36a8F9Cf47c347208E6B5D333) |

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
