# Deploy

This directory contains the scripts and constants to deploy to mainnet and testnets.

- [`Deploy.s.sol`](./Deploy.s.sol) - Common deploy script code
- [`LibDeployAddresses.sol`](./LibDeployAddresses.sol) - Address constants for each network
- [`Mainnet.s.sol`](./Mainnet.s.sol) - Mainnet deploy script
- [`Goerli.s.sol`](./Goerli.s.sol) - Goerli deploy script

## Make sure your JS is built!

In order to ensure deploys work, make sure your JS is built by running `yarn build:ts` before deploying

## Dry-run test deploys

By default (without including the `--broadcast` flag), forge scripts are executed as a dry-run, and the reporting tells you what would have happened on-chain.

```sh
// goerli deploy
ALCHEMY_API_KEY=<add-api-key> yarn deploy-dry:goerli

// mainnet deploy
ALCHEMY_API_KEY=<add-api-key> yarn deploy-dry:mainnet
```

## Real deploys

Add the `--rpc-url $RPC_URL` flag, `--private-key $PRIVATE_KEY` flag, and the `--broadcast` flag to execute the deploy script on-chain.

```sh
// goerli deploy
ALCHEMY_API_KEY=<your-api-key> PRIVATE_KEY=<your-private-key> yarn deploy:goerli

// mainnet deploy
ALCHEMY_API_KEY=<your-api-key> PRIVATE_KEY=<your-private-key> yarn deploy:mainnet
```

### More info

[`forge script` docs](https://book.getfoundry.sh/reference/forge/forge-script.html?highlight=script#forge-script)
