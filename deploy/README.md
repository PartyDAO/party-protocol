# deploy

This directory contains the scripts and constants to deploy to mainnet and rinkeby.

- [`deploy.sol`](./deploy.sol) - common deploy script code
- [`LibDeployAddresses.sol`](./LibDeployAddresses.sol) - address constants for each network
- [`mainnet.sol`](./mainnet.sol) - mainnet deploy script
- [`rinkeby.sol`](./rinkeby.sol) - rinkeby deploy script

```sh
// rinkeby deploy
forge script ./deploy/rinkeby.sol -vvv --fork-url https://eth-rinkeby.alchemyapi.io/v2/$ALCHEMY_API_KEY --optimize --optimizer-runs 999999

// mainnet deploy
forge script ./deploy/mainnet.sol -vvv --fork-url https://eth-mainnet.alchemyapi.io/v2/$ALCHEMY_API_KEY --optimize --optimizer-runs 999999
```

[`forge script` docs](https://book.getfoundry.sh/reference/forge/forge-script.html?highlight=script#forge-script)

```
Other flag options
==================

--optimize

--optimizer-runs 999999
```

### PartyBid v1 HardHat configs

- [hardhat config](https://github.com/PartyDAO/partybid/blob/main/hardhat.config.js)
- [mainnet config](https://github.com/PartyDAO/partybid/blob/main/deploy/configs/mainnet.json)
- [rinkeby config](https://github.com/PartyDAO/partybid/blob/main/deploy/configs/rinkeby.json)
