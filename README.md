# Hyperlane InterchainCreate2FactoryRouter

This repo contains a possible solution for https://github.com/hyperlane-xyz/hyperlane-monorepo/issues/2232.

The `InterchainCreate2FactoryRouter` would allow to deploy a contract on any given chain Hyperlane and the router are
deployed from another chain with the same conditions. This allows developers to just have a balance on one chain but
deploy contracts on multiple chains.

## Deploy the router

- Run `yarn install` to install all the dependencies
- Create a `.env` file base on the [.env.example file](./.env.example) file, and set the required variables depending
  which script you are going to run.

Set the following environment variables required for running all the scripts, on each network.

- `NETWORK`: the name of the network you want to run the script
- `API_KEY_ALCHEMY`: you Alchemy API key

If the network is not listed under the `rpc_endpoints` section of the [foundry.toml file](./foundry.toml) you'll have to
add a new entry for it.

For deploying the router you have to run the `yarn run:deployRouter`. Make sure the following environment variable are
set:

- `DEPLOYER_PK`: deployer private key
- `MAILBOX`: address of Hyperlane Mailbox contract on the chain
- `ROUTER_OWNER`: address of the router owner
- `PROXY_ADMIN`: address of the proxy admin. The router is deployed using a `TransparentUpgradeableProxy`
- `ISM_SALT`: a salt for deploying the ISM the router uses. The provided in this repo is an `RoutingIsm` which allows
  the user indicate the ISM used when sending the message
- `ROUTER_IMPLEMENTATION`: the address of an existing implementation in the network
- `ISM`: the address of an existing implementation in the network
- `CUSTOM_HOOK`: some custom hook address to be set, address zero indicates the Mailbox default hook should be used

For enrolling routers you have to run `yarn run:enrollRouters`. Make sure the following environment variable are set:

- `ROUTER_OWNER_PK`: the router's owner private key. Only the owner can enroll routers
- `ROUTER`: address of the local router
- `ROUTERS`: a list of routes addresses, separated by commas
- `DOMAINS`: the domains list of the routers to enroll, separated by commas

## Example usage

Running the example script `yarn run:interchainDeploy` would deploy a
[TestDeployContract](./script/utils/TestDeployContract.sol) from the chain you set on `NETWORK` to the one you set on
`DESTINATION_NETWORK` using the router set on `ROUTER` and the salt on `EXAMPLE_SALT`

## Installing Dependencies

Foundry typically uses git submodules to manage dependencies, but this template uses Node.js packages because
[submodules don't scale](https://twitter.com/PaulRBerg/status/1736695487057531328).

This is how to install dependencies:

1. Install the dependency using your preferred package manager, e.g. `bun install dependency-name`
   - Use this syntax to install from GitHub: `bun install github:username/repo-name`
2. Add a remapping for the dependency in [remappings.txt](./remappings.txt), e.g.
   `dependency-name=node_modules/dependency-name`

Note that OpenZeppelin Contracts is pre-installed, so you can follow that as an example.

## Usage

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ forge clean
```

### Compile

Compile the contracts:

```sh
$ forge build
```

### Coverage

Get a test coverage report:

```sh
$ forge coverage
```

### Deploy

Deploy to Anvil:

```sh
$ forge script script/Deploy.s.sol --broadcast --fork-url http://localhost:8545
```

For this script to work, you need to have a `MNEMONIC` environment variable set to a valid
[BIP39 mnemonic](https://iancoleman.io/bip39/).

For instructions on how to deploy to a testnet or mainnet, check out the
[Solidity Scripting](https://book.getfoundry.sh/tutorials/solidity-scripting.html) tutorial.

### Format

Format the contracts:

```sh
$ forge fmt
```

### Gas Usage

Get a gas report:

```sh
$ forge test --gas-report
```

### Lint

Lint the contracts:

```sh
$ bun run lint
```

### Test

Run the tests:

```sh
$ forge test
```

## License

This project is licensed under MIT.
