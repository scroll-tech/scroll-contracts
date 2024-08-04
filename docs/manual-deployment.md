# Manual Deployment @scroll-tech/scroll-contracts

## Overview

This document will guide you through manually deploying Scroll contracts to both layer 1 and layer 2 networks.

### Requirements

This repository requires `node` version>=20.12.2, `yarn` and `foundry` to be previously installed.

- **Node.js:** https://nodejs.org/en/download/package-manager
- **Yarn:** https://www.npmjs.com/package/yarn
- **Foundry:** https://book.getfoundry.sh/getting-started/installation

### Config

1. Create directory `volume` on the root directory of the repo (all config file will be put or generated under this directory)

```bash
mkdir volume
```

2. Create config file, and copy config variables from example file `./docker/config-example.toml`

```bash
cp ./docker/config-example.toml ./volume/config.toml
```

If you've previously launched Scroll chain cocomponents using Scroll-SDK, you may already have a config.toml file. If so directly copy it to `./volume/config.toml`.
**Important Note: If you are launching a scroll chain through scroll-sdk, make sure this config.toml file stay same as the one used in scroll-sdk.**

Details about the some important variables you may want to change:

| Configuration Variable           | Description                                                                              |
| -------------------------------- | ---------------------------------------------------------------------------------------- |
| L1_RPC_ENDPOINT                  | The RPC endpoint for the layer 1 network                                                 |
| L2_RPC_ENDPOINT                  | The RPC endpoint for the layer 2 network                                                 |
| CHAIN_ID_L1                      | The chain ID of the layer 1 network                                                      |
| CHAIN_ID_L2                      | The chain ID of the layer 2 network                                                      |
| DEPLOYER_PRIVATE_KEY             | The private key of the deployer on both layer 1 and layer 2                              |
| OWNER_PRIVATE_KEY                | The private key of the owner of Scroll contracts on both layer 1 and layer 2             |
| L1_COMMIT_SENDER_PRIVATE_KEY     | The private key of the commit sender (sequencer) on layer 1                              |
| L1_FINALIZE_SENDER_PRIVATE_KEY   | The private key of the finalize sender (prover) on layer 1                               |
| L1_GAS_ORACLE_SENDER_PRIVATE_KEY | The private key of the gas oracle sender on layer 1                                      |
| L2_GAS_ORACLE_SENDER_PRIVATE_KEY | The private key of the gas oracle sender on layer 2                                      |
| DEPLOYER_ADDR                    | The address of the deployer on both layer 1 and layer 2                                  |
| OWNER_ADDR                       | The address of the owner of Scroll contracts on both layer 1 and layer 2                 |
| L1_COMMIT_SENDER_ADDR            | The address of the commit sender (sequencer) on layer 1                                  |
| L1_FINALIZE_SENDER_ADDR          | The address of the finalize sender (prover) on layer 1                                   |
| L1_GAS_ORACLE_SENDER_ADDR        | The address of the gas oracle sender on layer 1                                          |
| L2_GAS_ORACLE_SENDER_ADDR        | The address of the gas oracle sender on layer 2                                          |
| DEPLOYMENT_SALT                  | The salt used to deploy contracts, make it unique to prevent contract address collisions |
| L1_CONTRACT_DEPLOYMENT_BLOCK     | The block that l2-sequencer and bridge-history-fetcher start to sync contracts event     |

### Deploy

1. Install packages

```bash
yarn install
```

2. Initialize git submodules.

```bash
git submodule update --init --recursive
```

3. Set and export environment variables (Change the RPCs to the one you are using)

```bash
export L1_RPC_ENDPOINT=http://l1-devnet.scrollsdk
export L2_RPC_ENDPOINT=http://l2-rpc.scrollsdk
```

4. Generate predicted contract addresses (This step required mainly because we are checking if every contracts deployed as we expected)

```bash
forge script scripts/deterministic/DeployScroll.s.sol:DeployScroll --sig "run(string,string)" "none" "write-config"
```

5. Deploy contracts on both layer1 and layer2 (Deployment may be interrupted by errors. Rerun the command to resume in such cases.)

```bash
./docker/scripts/deploy.sh
```
