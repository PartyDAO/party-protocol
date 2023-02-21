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

| Contract                      | Ethereum                                                                                                              | Goerli                                                                                                                       |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `CrowdfundFactory`            | [0x1cA200B6fa768d0CBe4b1C52B67dAEcad94838A6](https://etherscan.io/address/0x1cA200B6fa768d0CBe4b1C52B67dAEcad94838A6) | [0xa56b394E191dF03562d148216592d384F66bBa29](https://goerli.etherscan.io/address/0xa56b394E191dF03562d148216592d384F66bBa29) |
| `PartyFactory`                | [0x1Ca2007D4F2BC0eC2A56ECB890e56e05f36182dF](https://etherscan.io/address/0x1Ca2007D4F2BC0eC2A56ECB890e56e05f36182dF) | [0xD1bc5eED9a90911caa76A8EA1f11C4Ea012976FC](https://goerli.etherscan.io/address/0xD1bc5eED9a90911caa76A8EA1f11C4Ea012976FC) |
| `TokenDistributor`            | [0x1CA2007a81F8A7491BB6E11D8e357FD810896454](https://etherscan.io/address/0x1CA2007a81F8A7491BB6E11D8e357FD810896454) | [0xE6F58B31344404E3479d81fB8f9dD592feB37965](https://goerli.etherscan.io/address/0xE6F58B31344404E3479d81fB8f9dD592feB37965) |
| `AuctionCrowdfund`            | [0xC45e57873C1a2366F44Cbe5851a376f0Ab9093DA](https://etherscan.io/address/0xC45e57873C1a2366F44Cbe5851a376f0Ab9093DA) | [0xF620e947e5b664ee200996C7d74354BCfB39D1D9](https://goerli.etherscan.io/address/0xF620e947e5b664ee200996C7d74354BCfB39D1D9) |
| `RollingAuctionCrowdfund`     | [0x0d212feaE711aE9a065649ca577b4d6F4d67A0C6](https://etherscan.io/address/0x0d212feaE711aE9a065649ca577b4d6F4d67A0C6) | [0x44D31e47F2287A791441b8F330E6F4237eFB2FAb](https://goerli.etherscan.io/address/0x44D31e47F2287A791441b8F330E6F4237eFB2FAb) |
| `BuyCrowdfund`                | [0x79EbABbF5afA3763B6259Cb0a7d7f72ab59A2c47](https://etherscan.io/address/0x79EbABbF5afA3763B6259Cb0a7d7f72ab59A2c47) | [0xd380e07E277A03dfdB2E0fE44eaaA48621C588A0](https://goerli.etherscan.io/address/0xd380e07E277A03dfdB2E0fE44eaaA48621C588A0) |
| `CollectionBuyCrowdfund`      | [0xe944ecd23Dd7839077e1Fe04872eF93BfDe58bB3](https://etherscan.io/address/0xe944ecd23Dd7839077e1Fe04872eF93BfDe58bB3) | [0xf175C25243E25b47E7a3Cdef52b923fc628828b6](https://goerli.etherscan.io/address/0xf175C25243E25b47E7a3Cdef52b923fc628828b6) |
| `CollectionBatchBuyCrowdfund` | [0x8e357490dC8E94E9594AE910BA261163631a6a3a](https://etherscan.io/address/0x8e357490dC8E94E9594AE910BA261163631a6a3a) | [0xDe29e1A87f338B4B96c27Ca46195b5f9eda4a780](https://goerli.etherscan.io/address/0xDe29e1A87f338B4B96c27Ca46195b5f9eda4a780) |
| `Party`                       | [0x52010E220E5C8eF2217D86cfA58da51Da39e8ec4](https://etherscan.io/address/0x52010E220E5C8eF2217D86cfA58da51Da39e8ec4) | [0xa3b4A7110b48FDFf1970D787D1cdCB9679176464](https://goerli.etherscan.io/address/0xa3b4A7110b48FDFf1970D787D1cdCB9679176464) |
| `ProposalExecutionEngine`     | [0xa51eF92Ee7F24EFf05f5E5CC2119C22C4F8843F6](https://etherscan.io/address/0xa51eF92Ee7F24EFf05f5E5CC2119C22C4F8843F6) | [0xD36689563949DDF6FF01d89b514f6BFc2b443dDE](https://goerli.etherscan.io/address/0xD36689563949DDF6FF01d89b514f6BFc2b443dDE) |
| `CrowdfundNFTRenderer`        | [0x565846D035b2B02D6631d579eD34d8f250584015](https://etherscan.io/address/0x565846D035b2B02D6631d579eD34d8f250584015) | [0xe99446935bc7EF76f68cb0250f0E3e1C72371fB4](https://goerli.etherscan.io/address/0xe99446935bc7EF76f68cb0250f0E3e1C72371fB4) |
| `PartyNFTRenderer`            | [0xe3211390292300848428640bbc2F324D36a25857](https://etherscan.io/address/0xe3211390292300848428640bbc2F324D36a25857) | [0xeEf9Cd7a71d31054f794545308cf0503708B2980](https://goerli.etherscan.io/address/0xeEf9Cd7a71d31054f794545308cf0503708B2980) |
| `RendererStorage`             | [0x9A4fe89316bf81a1e4549476b219c456703C3F62](https://etherscan.io/address/0x9A4fe89316bf81a1e4549476b219c456703C3F62) | [0x35c3bD81F7b3E2ddCE70f2b9f2cA94aC9992EE23](https://goerli.etherscan.io/address/0x35c3bD81F7b3E2ddCE70f2b9f2cA94aC9992EE23) |
| `AllowListGatekeeper`         | [0x50c58f8bD97C1845C8E8ff56117DbCE8a5B009b2](https://etherscan.io/address/0x50c58f8bD97C1845C8E8ff56117DbCE8a5B009b2) | [0xADcec7b4Db7969DFf00b9e5304be8e0d1261d6B4](https://goerli.etherscan.io/address/0xADcec7b4Db7969DFf00b9e5304be8e0d1261d6B4) |
| `TokenGatekeeper`             | [0x26A7bd6161e4C6aE44620CFC6f7b9C3Daf83AD0b](https://etherscan.io/address/0x26A7bd6161e4C6aE44620CFC6f7b9C3Daf83AD0b) | [0xa6FbcE9898A34a1e6db5Dab699B20b6bfEfda8c3](https://goerli.etherscan.io/address/0xa6FbcE9898A34a1e6db5Dab699B20b6bfEfda8c3) |
| `Globals`                     | [0x1cA20040cE6aD406bC2A6c89976388829E7fbAde](https://etherscan.io/address/0x1cA20040cE6aD406bC2A6c89976388829E7fbAde) | [0x753e22d4e112a4D8b07dF9C4C578b116E3B48792](https://goerli.etherscan.io/address/0x753e22d4e112a4D8b07dF9C4C578b116E3B48792) |
| `FoundationMarketWrapper`     | [0x96e5b0519983f2f984324b926e6d28C3A4Eb92A1](https://etherscan.io/address/0x96e5b0519983f2f984324b926e6d28C3A4Eb92A1) | [0xc1bb865106E3c86B1804FfAaC7795F82c93c8ceF](https://goerli.etherscan.io/address/0xc1bb865106E3c86B1804FfAaC7795F82c93c8ceF) |
| `NounsMarketWrapper`          | [0x9319DAd8736D752C5c72DB229f8e1b280DC80ab1](https://etherscan.io/address/0x9319DAd8736D752C5c72DB229f8e1b280DC80ab1) | [0x8633B1f69DA83067AB1Ec85a3411DE354fBF96cD](https://goerli.etherscan.io/address/0x8633B1f69DA83067AB1Ec85a3411DE354fBF96cD) |
| `ZoraMarketWrapper`           | [0x11c07cE1315a3b92C9755F90cDF40B04b88c5731](https://etherscan.io/address/0x11c07cE1315a3b92C9755F90cDF40B04b88c5731) | [0x969Ee9Ea5cebc042b689bff8e5497F96808353AE](https://goerli.etherscan.io/address/0x969Ee9Ea5cebc042b689bff8e5497F96808353AE) |

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
