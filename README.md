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

A protocol for _group coordination_. The Party Protocol provides on-chain functionality for group formation, coordination, and distribution, with the goal of making Ethereum multiplayer.

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

For more information on Party Protocol, see the documentation [here](https://docs.partydao.org).

## Contributing

This is an open protocol, so if you are interested in contributing see [here](./CONTRIBUTING.md) for more details about how you could get involved.

## Layout

```
docs/ # Start here
├── overview.md
├── crowdfund.md
└── governance.md
contracts/
│   # Used during the crowdfund phase
├── crowdfund/
├── gatekeepers/
├── globals/
│   # Used during the governance phase
├── party/
├── proposals/
├── distribution/
|   # Used to render crowdfund and governance NFTs
└── renderers/
test/ # Foundry tests
```

## Deployments

Below are the latest deployments of each contract of the Party Protocol. For addresses of previous releases, see [here](https://github.com/PartyDAO/party-addresses).

| Contract                      | Ethereum                                                                                                              | Goerli                                                                                                                       | Base                                                                                                                  | Base Goerli                                                                                                                  |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `Globals`                     | [0x1ca20040ce6ad406bc2a6c89976388829e7fbade](https://etherscan.io/address/0x1ca20040ce6ad406bc2a6c89976388829e7fbade) | [0x753e22d4e112a4d8b07df9c4c578b116e3b48792](https://goerli.etherscan.io/address/0x753e22d4e112a4d8b07df9c4c578b116e3b48792) | [0xcEDe25DF327bD1619Fe25CDa2292e14edAC30717](https://basescan.org/address/0xcEDe25DF327bD1619Fe25CDa2292e14edAC30717) | [0x1b0e8E8DC71b29CE49038569dEF1B3Bc0120F602](https://goerli.basescan.org/address/0x1b0e8E8DC71b29CE49038569dEF1B3Bc0120F602) |
| `TokenDistributor`            | [0x0b7b86DCEAa8015CeD8F625d3b7A961b31fB05FE](https://etherscan.io/address/0x0b7b86DCEAa8015CeD8F625d3b7A961b31fB05FE) | [0x510c2F7e19a8f2537A3fe3Cf847e6583b993FA60](https://goerli.etherscan.io/address/0x510c2F7e19a8f2537A3fe3Cf847e6583b993FA60) | [0x65778953D291DD1e3a97c6b4d8BEea188B650077](https://basescan.org/address/0x65778953D291DD1e3a97c6b4d8BEea188B650077) | [0x1b5cB8bb71edA9059d39c98348095B008b67e734](https://goerli.basescan.org/address/0x1b5cB8bb71edA9059d39c98348095B008b67e734) |
| `ProposalExecutionEngine`     | [0xdf6a4d97dd2aa32a54b8a2b2711f210b711f28f0](https://etherscan.io/address/0xdf6a4d97dd2aa32a54b8a2b2711f210b711f28f0) | [0xc148E6f886CccdA5dEBbBA10d864d007E0C74c85](https://goerli.etherscan.io/address/0xc148E6f886CccdA5dEBbBA10d864d007E0C74c85) | [0xaec4D40045DaF91Bc3049ea9136C7dF04bD8a6af](https://basescan.org/address/0xaec4D40045DaF91Bc3049ea9136C7dF04bD8a6af) | [0xafE8265538F97e9F2Ff459F4aD871892a292419b](https://goerli.basescan.org/address/0xafE8265538F97e9F2Ff459F4aD871892a292419b) |
| `Party`                       | [0xb676cfeeed5c7b739452a502f1eff9ab684a56da](https://etherscan.io/address/0xb676cfeeed5c7b739452a502f1eff9ab684a56da) | [0x72a4b63eceA9465e3984CDEe1354b9CF9030c043](https://goerli.etherscan.io/address/0x72a4b63eceA9465e3984CDEe1354b9CF9030c043) | [0x65EBb1f88AA377ee56E8114234d5721eb4C5BAfd](https://basescan.org/address/0x65EBb1f88AA377ee56E8114234d5721eb4C5BAfd) | [0xe46b1B3D7eF3421D96F06D13d641dD702d44904e](https://goerli.basescan.org/address/0xe46b1B3D7eF3421D96F06D13d641dD702d44904e) |
| `PartyFactory`                | [0x2dFA21A5EbF5CcBE62566458A1baEC6B1F33f292](https://etherscan.io/address/0x2dFA21A5EbF5CcBE62566458A1baEC6B1F33f292) | [0x83e63E8bAba6C6dcb9F3F4324bEfA72AD8f43e44](https://goerli.etherscan.io/address/0x83e63E8bAba6C6dcb9F3F4324bEfA72AD8f43e44) | [0xF8c8fC091C0Cc94a9029d6443050bDfF9097E38A](https://basescan.org/address/0xF8c8fC091C0Cc94a9029d6443050bDfF9097E38A) | [0xa7C2ede6A4ebdE4EE86E600D339F9F236B8C1275](https://goerli.basescan.org/address/0xa7C2ede6A4ebdE4EE86E600D339F9F236B8C1275) |
| `AuctionCrowdfund`            | [0xcf8ab207e1b055871dfa9be2a0cf3acaf2d1b3a7](https://etherscan.io/address/0xcf8ab207e1b055871dfa9be2a0cf3acaf2d1b3a7) | [0x631D392073330f0573AD18Fc64305768657D0D60](https://goerli.etherscan.io/address/0x631D392073330f0573AD18Fc64305768657D0D60) | [0xcF8ab207E1b055871dfa9be2a0Cf3acAf2d1b3A7](https://basescan.org/address/0xcF8ab207E1b055871dfa9be2a0Cf3acAf2d1b3A7) | [0x70a842F6131031266438171731f1d2ACfd9EC891](https://goerli.basescan.org/address/0x70a842F6131031266438171731f1d2ACfd9EC891) |
| `RollingAuctionCrowdfund`     | [0x1b5cb8bb71eda9059d39c98348095b008b67e734](https://etherscan.io/address/0x1b5cb8bb71eda9059d39c98348095b008b67e734) | [0x989Fb364065a80d732837742f960924f343C6E04](https://goerli.etherscan.io/address/0x989Fb364065a80d732837742f960924f343C6E04) | [0x2e8920950677F8545B4Ef80315f48E161CB02D1C](https://basescan.org/address/0x2e8920950677F8545B4Ef80315f48E161CB02D1C) | [0x73B66c97e53301651E69D10743352B411d480c3f](https://goerli.basescan.org/address/0x73B66c97e53301651E69D10743352B411d480c3f) |
| `BuyCrowdfund`                | [0x104db1e49b87c80ec2e2e9716e83a304415c15ce](https://etherscan.io/address/0x104db1e49b87c80ec2e2e9716e83a304415c15ce) | [0x712Dca72Cc443A5f5e03A388b69ab09b4CDAC428](https://goerli.etherscan.io/address/0x712Dca72Cc443A5f5e03A388b69ab09b4CDAC428) | [0x104db1E49b87C80Ec2E2E9716e83A304415C15Ce](https://basescan.org/address/0x104db1E49b87C80Ec2E2E9716e83A304415C15Ce) | [0x4a043c81b2D321C6768f607C2f2E6482CDeCadD0](https://goerli.basescan.org/address/0x4a043c81b2D321C6768f607C2f2E6482CDeCadD0) |
| `CollectionBuyCrowdfund`      | [0x8ba53d174c540833d7f87e6ef97fc85d3d9291b4](https://etherscan.io/address/0x8ba53d174c540833d7f87e6ef97fc85d3d9291b4) | [0x884561d34e6B98a11DaF9Cc5d0d50cEFC664262F](https://goerli.etherscan.io/address/0x884561d34e6B98a11DaF9Cc5d0d50cEFC664262F) | [0x8bA53D174C540833d7F87e6Ef97Fc85d3d9291b4](https://basescan.org/address/0x8bA53D174C540833d7F87e6Ef97Fc85d3d9291b4) | [0x5534C682AebEFA85CA8c955bf324739a3D259284](https://goerli.basescan.org/address/0x5534C682AebEFA85CA8c955bf324739a3D259284) |
| `CollectionBatchBuyCrowdfund` | [0x05daeace2257de1633cb809e2a23387a2742535c](https://etherscan.io/address/0x05daeace2257de1633cb809e2a23387a2742535c) | [0x9926816276CFE4E7c230E14d5a8808C9709Fa51a](https://goerli.etherscan.io/address/0x9926816276CFE4E7c230E14d5a8808C9709Fa51a) | [0x05daeacE2257De1633cb809E2A23387a2742535c](https://basescan.org/address/0x05daeacE2257De1633cb809E2A23387a2742535c) | [0x36DdCBd450aF74bd8D3F7e1Dc24AB5b3091289c7](https://goerli.basescan.org/address/0x36DdCBd450aF74bd8D3F7e1Dc24AB5b3091289c7) |
| `CrowdfundFactory`            | [0xce636adbFCdB6c487c69D4f92603714c2450a0c9](https://etherscan.io/address/0xce636adbFCdB6c487c69D4f92603714c2450a0c9) | [0x5bFADA22929Ce611894c5ba0A1d583459f3f3858](https://goerli.etherscan.io/address/0x5bFADA22929Ce611894c5ba0A1d583459f3f3858) | [0xDe0073207C36A2A8Bc8bb5634f1db74d35b015f9](https://basescan.org/address/0xDe0073207C36A2A8Bc8bb5634f1db74d35b015f9) | [0x4F2843E6C02F3bbD9F4004fC0Ac7FB6e31b5EFb0](https://goerli.basescan.org/address/0x4F2843E6C02F3bbD9F4004fC0Ac7FB6e31b5EFb0) |
| `CrowdfundNFTRenderer`        | [0x899658a410eDd5d6AE766933385fbFE0C4504b3F](https://etherscan.io/address/0x899658a410eDd5d6AE766933385fbFE0C4504b3F) | [0xcF8ab207E1b055871dfa9be2a0Cf3acAf2d1b3A7](https://goerli.etherscan.io/address/0xcF8ab207E1b055871dfa9be2a0Cf3acAf2d1b3A7) | [0x19BcAc3761Df79c9b242Ebe6670898DA7D4bDCB3](https://basescan.org/address/0x19BcAc3761Df79c9b242Ebe6670898DA7D4bDCB3) | [0xCE03B805c942a1DDdaaAD4F7a1C2BC00A96baf75](https://goerli.basescan.org/address/0xCE03B805c942a1DDdaaAD4F7a1C2BC00A96baf75) |
| `AllowListGateKeeper`         | [0x65778953D291DD1e3a97c6b4d8BEea188B650077](https://etherscan.io/address/0x65778953D291DD1e3a97c6b4d8BEea188B650077) | [0x554A3b66Fcd3c9eb7730b21F207a28F1e4954142](https://goerli.etherscan.io/address/0x554A3b66Fcd3c9eb7730b21F207a28F1e4954142) | [0x0EC569Ed2E3D2a61562Ae76539A84b1948F0c7a6](https://basescan.org/address/0x0EC569Ed2E3D2a61562Ae76539A84b1948F0c7a6) | [0x0D43100FcB0F4AbBE7d650440828b3Db80742098](https://goerli.basescan.org/address/0x0D43100FcB0F4AbBE7d650440828b3Db80742098) |
| `TokenGateKeeper`             | [0xa9f550971Fc0431d7DbaA667c92061eD9a1B8E90](https://etherscan.io/address/0xa9f550971Fc0431d7DbaA667c92061eD9a1B8E90) | [0x7FCC6b4c437aA78E6C432d4A459Ae644514Be638](https://goerli.etherscan.io/address/0x7FCC6b4c437aA78E6C432d4A459Ae644514Be638) | [0x9A1C1e8eBD7e50A1280A31d736388A50f3d96a4D](https://basescan.org/address/0x9A1C1e8eBD7e50A1280A31d736388A50f3d96a4D) | [0xF940e28d4320F794150DFB40c7f2f65E371808e6](https://goerli.basescan.org/address/0xF940e28d4320F794150DFB40c7f2f65E371808e6) |
| `PartyNFTRenderer`            | [0xFaF502852F927Fbc5e3c3040648aB968E43bf0b2](https://etherscan.io/address/0xFaF502852F927Fbc5e3c3040648aB968E43bf0b2) | [0xA4DDE8076A9B88F53f80d5Dc508D0656d7Db210D](https://goerli.etherscan.io/address/0xA4DDE8076A9B88F53f80d5Dc508D0656d7Db210D) | [0xAfeEf01d3267bf2dd500a3f988Dc51B52ceCF0Ed](https://basescan.org/address/0xAfeEf01d3267bf2dd500a3f988Dc51B52ceCF0Ed) | [0xc0e0ec5541e26E93D5a9f5E999AB2A0A7F8260ae](https://goerli.basescan.org/address/0xc0e0ec5541e26E93D5a9f5E999AB2A0A7F8260ae) |
| `MetadataRegistry`            | [0xEaf5bBC6c0FfF2Cc75BEb3fc8b53447570A1A2ED](https://etherscan.io/address/0xEaf5bBC6c0FfF2Cc75BEb3fc8b53447570A1A2ED) | [0x59E2844F9ADb537a97011528E699f76934Ef7cc9](https://goerli.etherscan.io/address/0x59E2844F9ADb537a97011528E699f76934Ef7cc9) | [0xA4DDE8076A9B88F53f80d5Dc508D0656d7Db210D](https://basescan.org/address/0xA4DDE8076A9B88F53f80d5Dc508D0656d7Db210D) | [0x39Aa347879C782F1375386FE8f7a39B203fB2e5c](https://goerli.basescan.org/address/0x39Aa347879C782F1375386FE8f7a39B203fB2e5c) |
| `InitialETHCrowdfund`         | [0xd2933a444D8771F265712962BE24096cEa041e0c](https://etherscan.io/address/0xd2933a444D8771F265712962BE24096cEa041e0c) | [0xea6b9F59aeEeD48e60548dDe5e32480cfF1eC447](https://goerli.etherscan.io/address/0xea6b9F59aeEeD48e60548dDe5e32480cfF1eC447) | [0x23C886396CFbaDB0F3bAC4b728150e8A59dC0E10](https://basescan.org/address/0x23C886396CFbaDB0F3bAC4b728150e8A59dC0E10) | [0x6a360CAee9a8313c64c72Fa2eB8E59F9B5218368](https://goerli.basescan.org/address/0x6a360CAee9a8313c64c72Fa2eB8E59F9B5218368) |
| `CollectionBatchBuyOperator`  | [0x119c7ee43ebf1dedc45a3730735583bd39e32579](https://etherscan.io/address/0x119c7ee43ebf1dedc45a3730735583bd39e32579) | [0x039d2e6AEf994445b00b6B55524bAcA0B0Be78DB](https://goerli.etherscan.io/address/0x039d2e6AEf994445b00b6B55524bAcA0B0Be78DB) | [0x510c2F7e19a8f2537A3fe3Cf847e6583b993FA60](https://basescan.org/address/0x510c2F7e19a8f2537A3fe3Cf847e6583b993FA60) | [0x4fD82CF0C955Acc0715Ef1440b8D1F2768C9a278](https://goerli.basescan.org/address/0x4fD82CF0C955Acc0715Ef1440b8D1F2768C9a278) |
| `ERC20SwapOperator`           | [0xd9f65f0d2135bee238db9c49558632eb6030caa7](https://etherscan.io/address/0xd9f65f0d2135bee238db9c49558632eb6030caa7) | [0x88B08D166cf2779c1E2ef6C1171214E782831814](https://goerli.etherscan.io/address/0x88B08D166cf2779c1E2ef6C1171214E782831814) | [0xdF6a4d97dd2Aa32a54B8a2b2711F210b711F28f0](https://basescan.org/address/0xdF6a4d97dd2Aa32a54B8a2b2711F210b711F28f0) | [0xca874ED4D1828aE092250d5F00F1C206A944baA4](https://goerli.basescan.org/address/0xca874ED4D1828aE092250d5F00F1C206A944baA4) |
| `MetadataProvider`            | [0xBC98Afde1DDCc9c17a8E69157b83b8971007cF92](https://etherscan.io/address/0xBC98Afde1DDCc9c17a8E69157b83b8971007cF92) | [0xC9846AD49F40bc66217280731Fc8EaEA37231979](https://goerli.etherscan.io/address/0xC9846AD49F40bc66217280731Fc8EaEA37231979) | [0xe06e71867bB25Fe6b56b854500961D4D9dd7c12e](https://basescan.org/address/0xe06e71867bB25Fe6b56b854500961D4D9dd7c12e) | [0x480f02Ca2E29A71bac6E314879E487a49a237E1B](https://goerli.basescan.org/address/0x480f02Ca2E29A71bac6E314879E487a49a237E1B) |
| `AtomicManualParty`           | [0x4a4D5126F99e58466Ceb051d17661bAF0BE2Cf93](https://etherscan.io/address/0x4a4D5126F99e58466Ceb051d17661bAF0BE2Cf93) | [0xb24aa5a8E4a6bb691DF4B722E79Da7842BFB8A68](https://goerli.etherscan.io/address/0xb24aa5a8E4a6bb691DF4B722E79Da7842BFB8A68) | [0xA138Bc79434Be2e134174f59277092F22b23bA91](https://basescan.org/address/0xA138Bc79434Be2e134174f59277092F22b23bA91) | [0x1B78e1801C83c176161101d448E27FbCD66f178e](https://goerli.basescan.org/address/0x1B78e1801C83c176161101d448E27FbCD66f178e) |
| `ContributionRouter`          | [0x2A93E97E84a532009DcAcC897295c6387Fd5c7e9](https://etherscan.io/address/0x2A93E97E84a532009DcAcC897295c6387Fd5c7e9) | [0x2EAf43684FF4655FC2Dd5827Ce9302c82eEc7a51](https://goerli.etherscan.io/address/0x2EAf43684FF4655FC2Dd5827Ce9302c82eEc7a51) | [0xD9F65f0d2135BeE238db9c49558632Eb6030CAa7](https://basescan.org/address/0xD9F65f0d2135BeE238db9c49558632Eb6030CAa7) | [0x53998d625B7Bb9252af9C5324a639e5Ca7bc50bF](https://goerli.basescan.org/address/0x53998d625B7Bb9252af9C5324a639e5Ca7bc50bF) |
| `BasicMetadataProvider`       | [0x70f80ae910081409DF29c6D779Cd83208B751636](https://etherscan.io/address/0x70f80ae910081409DF29c6D779Cd83208B751636) | [0x8816cec81d3221a8bc6c0760bcb33e646d355efb](https://goerli.etherscan.io/address/0x8816cec81d3221a8bc6c0760bcb33e646d355efb) | [0x39244498E639C4B24910E73DFa3622881D456724](https://basescan.org/address/0x39244498E639C4B24910E73DFa3622881D456724) | [0x104db1E49b87C80Ec2E2E9716e83A304415C15Ce](https://goerli.basescan.org/address/0x104db1E49b87C80Ec2E2E9716e83A304415C15Ce) |
| `SSTORE2MetadataProvider`     | [0xD665c633920c79cD1cD184D08AAC2cDB2711073c](https://etherscan.io/address/0xD665c633920c79cD1cD184D08AAC2cDB2711073c) | [0xdc693c350fbfe628d11f21ab154f0abec958fc61](https://goerli.etherscan.io/address/0xdc693c350fbfe628d11f21ab154f0abec958fc61) | [0xFaF502852F927Fbc5e3c3040648aB968E43bf0b2](https://basescan.org/address/0xFaF502852F927Fbc5e3c3040648aB968E43bf0b2) | [0x8bA53D174C540833d7F87e6Ef97Fc85d3d9291b4](https://goerli.basescan.org/address/0x8bA53D174C540833d7F87e6Ef97Fc85d3d9291b4) |
| `AddPartyCardsAuthority`      | [0xC534bb3640A66fAF5EAE8699FeCE511e1c331cAD](https://etherscan.io/address/0xC534bb3640A66fAF5EAE8699FeCE511e1c331cAD) | [0xaf308964C34De533c4110776e33B4a8a03f9fE79](https://goerli.etherscan.io/address/0xaf308964C34De533c4110776e33B4a8a03f9fE79) | [0x4a4D5126F99e58466Ceb051d17661bAF0BE2Cf93](https://basescan.org/address/0x4a4D5126F99e58466Ceb051d17661bAF0BE2Cf93) | [0x05daeacE2257De1633cb809E2A23387a2742535c](https://goerli.basescan.org/address/0x05daeacE2257De1633cb809E2A23387a2742535c) |

## Install

First, install [Foundry](https://book.getfoundry.sh/getting-started/installation.html).

```bash
forge install
yarn -D
yarn build
yarn build:ts
```

## Testing

### Run tests (except fork tests):

```bash
forge test -vv
# If you want gas reports:
forge test --gas-report -vv
```

### Run forked tests

```bash
forge test --mt testFork --fork-url $YOUR_RPC_URL -vv
```

### Run all tests

```bash
forge test --fork-url $YOUR_RPC_URL -vv
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
| 6. Critical | - Draining or freezing of holdings protocol-wide (e.g. draining token distributor, economic attacks, reentrancy, MEV, logic errors)                                                              | Let's talk             |
| 5. Severe   | - Contracts with balances can be exploited to steal holdings under specific conditions (e.g. bypass guardrails to transfer precious NFT from parties, user can steal their party's distribution) | Up to 25 ETH           |
| 4. High     | - Contracts temporarily unable to transfer holdings<br>- Users spoof each other                                                                                                                  | Up to 10 ETH           |
| 3. Medium   | - Contract consumes unbounded gas<br>- Griefing, denial of service (i.e. attacker spends as much in gas as damage to the contract)                                                               | Up to 5 ETH            |
| 2. Low      | - Contract fails to behave as expected, but doesn't lose value                                                                                                                                   | Up to 1 ETH            |
| 1. None     | - Best practices                                                                                                                                                                                 |                        |

Any vulnerability or bug discovered must be reported only to the following email: [security@partydao.org](mailto:security@partydao.org).

## License

The primary license for the Party Protocol is the GNU General Public License 3.0 (`GPL-3.0`), see [LICENSE](./LICENSE).

- Several interface/dependencies files from other sources maintain their original license (as indicated in their SPDX header).
- All files in `test/` remain unlicensed (as indicated in their SPDX header).
