# Architecture Overview

## Background

Our AA wallet technology has been designed to support multiple use cases and business scenarios:

- **Passkey Wallets**: Provide novice users with wallets that don't require private key backup, support account recovery, and can operate gas-free on supported chains. This solution reduces the barrier to Web3 usage, making it easy for users to quickly get started in payment and social scenarios. We've adopted the industry-proven ERC-4337 standard as the underlying account architecture.
- **EOA Upgrades (EIP-7702)**: Target Web3 native users who already have EOA wallets, supporting upgrades from traditional wallets to smart contract wallets. This allows users to enjoy the automation and flexibility advantages brought by AA. This solution focuses on reducing on-chain operation costs through a non-4337 architecture contract account system to achieve higher gas efficiency.

## Architecture Design

As our AA wallet service expands, we've designed a architecture to improve maintainability, flexibility, and reusability.

### Design Principles

1. **Full Reuse**: Leverage core advantages of existing schemes
2. **Industry Benchmarking**: Reference contract design from Uniswap, MetaMask, and Coinbase
3. **Contract Account Architecture**: Meet differentiated needs of multiple products

### Key Characteristics

#### 1. Multi-Product Compatibility

- **Passkey wallets** for novice users
- **Advanced feature wallets** for native users
- **Exchange users** (KYC) vs **Web3 users** (non-KYC)
- **Shared underlying architecture**

#### 2. Flexible Account Recovery

- **Passkey recovery**
- **ZKEmail**
- **SocialID**
- **Product-specific access** as needed

#### 3. Easy Expansion and Maintenance

- **Modularization** of underlying architecture
- **Abstract design** for future products/features
- **Efficient development** of new capabilities

## Technical Architecture

### Core Components & Technical Decisions

1. **OwnerManager**: Multi-owner support with flexible permissions
  - Packed settings for efficient storage
  - Admin privileges: can call both internal and external functions
  - Non-admin owners: can only call external functions
  - Time-based access control for temporary permissions
  - Hook system for extensible functionality
2. **NonceManager**: 2-dimensional nonce management (key + sequence)
  - `uint256 nonce = uint192 key + uint64 value` structure
  - Concurrent execution support through different nonce keys
  - Parallel transaction processing without nonce conflicts
  - Chainless operations (nonce key = 196): limited to upgrade contract and addOwner functions only
3. **Execute**: Multiple execution modes (direct, relayer, 4337)
  - Direct execution for owner-only operations
  - Relayer execution with `validUntil` timestamp for signature expiration control
  - ERC-4337 compatible execution through EntryPoint with `validUntil` support in `validateUserOp`
  - Time-bound signatures prevent replay attacks and enable transaction deadlines
4. **Validator**: Support for ECDSA, Passkey, and Merkle Tree
  - Address-based routing for different authentication methods
  - Efficient proof verification through Merkle Tree integration
  - Multi-signature support for flexible ownership structures
5. **Recovery**: Flexible account recovery mechanisms
  - Multiple recovery methods: ZKEmail, SocialID, EOA
  - Recovery signer factory with deterministic address generation
  - Verifier-based recovery for secure account restoration
6. **ERC-4337 Compatibility**
  - Full compatibility with industry standard
  - Backward compatibility for existing integrations
  - Future-proof design for emerging standards

## Benefits of Architecture

1. **Reduced Development Time**: Shared components across products
2. **Improved Security**: Centralized security audits and updates
3. **Better User Experience**: Consistent behavior across different wallet types
4. **Easier Maintenance**: Single codebase for core functionality
5. **Faster Innovation**: New features benefit all products simultaneously

## Essential Diagrams

### Contract Infrastructure Diagram

Shows the overall contract architecture and relationships between the product, service and contract layers.

Contract Infrastructure

### Account Creation Flow

Illustrates the account creation options including a Smart Wallet contract deployment, or delegation via EIP-7702.

Account Creation Flow

### Owner and Validation Types

Multiple types of ownership are supported, each mapped to its specific validator and dynamically routed. The system automatically routes authentication requests based on the owner type, allowing the wallet to support diverse user preferences while maintaining security through appropriate validation mechanisms for each authentication type.

Owner Validation Types

### Execution Flow

Shows the three execution modes and their flows: direct execution, relayer execution, and ERC-4337 execution paths via the Smart Wallet.

Execution Flow

### Recovery Flow

Illustrates the account recovery process including recovery trigger, verification, and ownership addition.

Recovery Flow