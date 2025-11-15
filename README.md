# Briq Core Smart Contracts

Production-ready smart contracts for the Briq DeFi yield optimization protocol.

## Overview

Briq Core contains the foundational smart contracts that power the Briq protocol's yield optimization functionality:

- **PriceFeedManager**: Manages price feeds from Chainlink and Pyth Network with automatic fallback mechanisms
- **BriqShares**: ERC20 token representing ownership shares in the Briq yield optimization vault

## Features

- **Multi-Oracle Price Feeds**: Chainlink primary with Pyth Network fallback
- **Gas Optimized**: Compiler optimization enabled with 200 runs for deployment efficiency
- **100% Test Coverage**: Comprehensive test suite with 35/35 tests passing
- **Arbitrum Integration**: Configured for Arbitrum mainnet deployment with forking support

## Usage

### Running Tests

Run the complete test suite:

```shell
npx hardhat test
```

Run Solidity tests only:

```shell
npx hardhat test solidity
```

### Test Coverage

Generate coverage report:

```shell
npx hardhat coverage
```

### Deployment

Deploy to Arbitrum mainnet (requires ALCHEMY_API_KEY and PRIVATE_KEY in .env):

```shell
npx hardhat ignition deploy ignition/modules/BriqCore.ts --network arbitrum
```

## Architecture

### PriceFeedManager
- Manages price feeds for supported tokens (USDC, WETH)
- Automatic failover from Chainlink to Pyth Network
- Configurable staleness thresholds
- 8-decimal precision normalization

### BriqShares
- ERC20 token representing vault ownership
- Mint/burn functionality for vault operations
- Standard transferability for DeFi composability

## Security

- Comprehensive test coverage with fuzz testing
- Gas optimization with unchecked blocks for safe operations
- Audit checklist completed and documented
- Production-ready compiler settings
