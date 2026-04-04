## Refund Protocol

A protocol for handling refunds and chargebacks in a non-custodial manner. This protocol introduces an arbiter system that can mediate disputes between payment senders and receivers, providing a better user experience to stablecoin payments while still allowing receivers to retain control over their funds.

## Setup

### Prerequisites

1. Install Foundry:
```shell
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Initialize submodules:
```shell
git submodule update --init --recursive
```

## Development

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Deploy (Base mainnet, Base Sepolia, Arc testnet, etc.)

Use the same `forge script` flow on every chain: set `PRIVATE_KEY`, `ARBITER_ADDRESS`, and `USDC_ADDRESS` to that network’s USDC (or test token), then point `--rpc-url` at the chain.

**Base mainnet (chain id 8453)** — USDC: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

```shell
export PRIVATE_KEY=...                    # deployer (needs ETH on Base for gas)
export ARBITER_ADDRESS=0x...              # arbiter EOA / multisig
export USDC_ADDRESS=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
export BASE_MAINNET_RPC_URL=https://mainnet.base.org   # or your provider URL

forge script script/DeployRefundProtocol.s.sol:DeployRefundProtocol \
  --rpc-url base \
  --broadcast \
  -vvvv
```

**Base Sepolia** — set `USDC_ADDRESS` to your Sepolia USDC (e.g. Circle test USDC on Base Sepolia) and `BASE_SEPOLIA_RPC_URL`, then:

```shell
forge script script/DeployRefundProtocol.s.sol:DeployRefundProtocol \
  --rpc-url base-sepolia \
  --broadcast \
  -vvvv
```

Optional: `EIP712_NAME` and `EIP712_VERSION` (defaults match tests: `Refund Protocol` / `1.0`).

## License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.
