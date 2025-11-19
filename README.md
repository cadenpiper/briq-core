# briq-core

briq-core contains the foundational smart contracts that power the Briq protocol.

## Features

- **PriceFeedManager**: Dual-oracle price feed system with Chainlink primary + Pyth Network fallback
- **BriqTimelock**: OpenZeppelin TimelockController with 48-hour delay for governance operations
- **Dual-Oracle Price Feeds**: Chainlink primary with Pyth Network automatic fallback
- **Governance Security**: 48-hour timelock for critical operations
- **Gas Optimized**: Custom errors and compiler optimization for deployment efficiency
- **100% Test Coverage**: Comprehensive test suite with TypeScript integration
- **Arbitrum Integration**: Real oracle testing on forked Arbitrum mainnet

## Contracts

- **PriceFeedManager**: 100% tested, dual-oracle system
- **BriqTimelock**: Secure timelock implementation with OpenZeppelin base
- **BriqShares**: 100% tested, optimized, secure ERC20 implementation

## Usage

### Running Tests

```shell
npm test test/fileName --network hardhat
```

### Deployment

Deploy to Arbitrum mainnet:
```shell
npx hardhat ignition deploy ignition/modules/BriqCore.ts --network arbitrum
```

## Architecture

### PriceFeedManager
- **Dual-Oracle System**: Chainlink (1-hour staleness) + Pyth (20-second staleness)
- **Automatic Fallback**: Seamless failover when primary oracle is stale
- **Price Validation**: Sanity checks, round data validation, temporal verification
- **USD Conversion**: getTokenValueInUSD, convertUsdToToken utility functions
- **Access Control**: Owner/timelock restricted configuration

### BriqTimelock
- **OpenZeppelin Base**: Inherits battle-tested TimelockController
- **48-Hour Delay**: Security buffer for critical operations
- **Custom Errors**: Gas-optimized NotAdmin() error
- **Role Management**: Proper admin and executor role handling

### BriqShares
- **ERC20 Standard**: Full compatibility with DeFi ecosystem
- **Vault Integration**: Mint/burn functionality for vault operations
- **Access Control**: Vault-only minting with owner configuration
- **Gas Optimized**: Custom errors and efficient storage patterns

## Security

### Completed Security Measures
- ✅ **Dual-Oracle Protection**: Eliminates single point of failure
- ✅ **Staleness Validation**: Prevents stale price data usage
- ✅ **Access Control**: Timelock integration for critical functions
- ✅ **Custom Errors**: Gas-efficient error handling
- ✅ **Comprehensive Testing**: 100% coverage with real oracle data

## Development

### Prerequisites
- Node.js 18+
- Hardhat
- TypeScript
- Alchemy API key for Arbitrum forking

### Environment Setup
```shell
# Install dependencies
npm install

# Set up Hardhat keystore for secure secret management
# For development environment variables, add --dev
# Add your Alchemy API key (required for Arbitrum forking in tests)
npx hardhat keystore set ARBITRUM_RPC_URL
# Enter your Alchemy API key when prompted

# For deployment, add private key (optional)
npx hardhat keystore set PRIVATE_KEY
# Enter your private key when prompted

# Verify keystore setup
npx hardhat keystore list
```

**Note**: The keystore encrypts and stores secrets locally. Tests and deployment will automatically use these values from the keystore without needing `.env` files.
