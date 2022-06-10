# deploy

This directory contains the scripts and constants to deploy to mainnet and rinkeby.

- [`deploy.sol`](./deploy.sol) - common deploy script code
- [`LibDeployAddresses.sol`](./LibDeployAddresses.sol) - address constants for each network
- [`mainnet.sol`](./mainnet.sol) - mainnet deploy script
- [`rinkeby.sol`](./rinkeby.sol) - rinkeby deploy script

## ⚠️ Modify forge-std `Vm.sol` locally

At the time of writing this, the file `lib/forget-std/src/Vm.sol` needed to be modified to include the broadcast methods in its interface. Apply the following diff to `lib/forget-std/src/Vm.sol` starting at the end of the file (line 73):

```diff
    // Set block.coinbase (who)
    function coinbase(address) external;
+    // Using the address that calls the test contract, has the next call (at this call depth only) create a transaction that can later be signed and sent onchain
+    function broadcast() external;
+    // Has the next call (at this call depth only) create a transaction with the address provided as the sender that can later be signed and sent onchain
+    function broadcast(address) external;
+    // Using the address that calls the test contract, has the all subsequent calls (at this call depth only) create transactions that can later be signed and sent onchain
+    function startBroadcast() external;
+    // Has the all subsequent calls (at this call depth only) create transactions that can later be signed and sent onchain
+    function startBroadcast(address) external;
+    // Stops collecting onchain transactions
+    function stopBroadcast() external;
}

```

## Dry-run test deploys

By default (without including the `--broadcast` flag), forge scripts are executed as a dry-run, and the reporting tells you what would have happened on-chain.

```sh
// rinkeby deploy
forge script ./deploy/rinkeby.sol -vvv --fork-url https://eth-rinkeby.alchemyapi.io/v2/$ALCHEMY_API_KEY --optimize --optimizer-runs 999999

// mainnet deploy
forge script ./deploy/mainnet.sol -vvv --fork-url https://eth-mainnet.alchemyapi.io/v2/$ALCHEMY_API_KEY --optimize --optimizer-runs 999999
```

## Real deploys

Add the `--rpc-url $RPC_URL` flag, --private-key $PRIVATE_KEY, and the `--broadcast` flag to execute the deploy script on-chain.

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
