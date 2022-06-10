# deploy

This directory contains the scripts and constants to deploy to mainnet and rinkeby.

- [`deploy.sol`](./deploy.sol) - common deploy script code
- [`LibDeployAddresses.sol`](./LibDeployAddresses.sol) - address constants for each network
- [`mainnet.sol`](./mainnet.sol) - mainnet deploy script
- [`rinkeby.sol`](./rinkeby.sol) - rinkeby deploy script

### Dry-run test deploys

```sh
// rinkeby deploy
forge script ./deploy/rinkeby.sol -vvv --fork-url https://eth-rinkeby.alchemyapi.io/v2/$ALCHEMY_API_KEY --optimize --optimizer-runs 999999

// mainnet deploy
forge script ./deploy/mainnet.sol -vvv --fork-url https://eth-mainnet.alchemyapi.io/v2/$ALCHEMY_API_KEY --optimize --optimizer-runs 999999
```

### Real deploys

```sh
// rinkeby deploy
forge script ./deploy/deploy.sol -vvv --rpc-url https://eth-rinkeby.alchemyapi.io/v2/$ALCHEMY_API_KEY --private-key $PRIVATE_KEY --broadcast --optimize --optimizer-runs 999999

// mainnet deploy
forge script ./deploy/deploy.sol -vvv --rpc-url https://eth-mainnet.alchemyapi.io/v2/$ALCHEMY_API_KEY --private-key $PRIVATE_KEY --broadcast --optimize --optimizer-runs 999999
```

### More info

[`forge script` docs](https://book.getfoundry.sh/reference/forge/forge-script.html?highlight=script#forge-script)

```
Other flag options
==================

--broadcast # does a real deploy. if omitted, the command will be a dry-run
--optimize
--optimizer-runs 999999
--verify # verifies contract source on etherscan. can also be done separately with the `forge verify-contract` command
```

### PartyBid v1 HardHat configs

- [hardhat config](https://github.com/PartyDAO/partybid/blob/main/hardhat.config.js)
- [mainnet config](https://github.com/PartyDAO/partybid/blob/main/deploy/configs/mainnet.json)
- [rinkeby config](https://github.com/PartyDAO/partybid/blob/main/deploy/configs/rinkeby.json)
