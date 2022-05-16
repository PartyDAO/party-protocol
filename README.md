# partybidV2

## Building

First install [foundry](https://book.getfoundry.sh/getting-started/installation.html)

```
forge install
yarn -D
yarn build
```

## Testing

``
# run all tests (except fork tests)
yarn test
# run only ts tests
yarn test:ts
# run only solidity tests
yarn test:sol
# run fork tests
forge test --fork-url $YOUR_RPC_URL
```
