# deploy

```sh
forge script ./deploy/deploy.sol -vvv --fork-url https://eth-mainnet.alchemyapi.io/v2/$ALCHEMY_API_KEY --optimize --optimizer-runs 999999
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
