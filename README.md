# Firewall Vault Core

**Protected version of your wallet**

Firewall Vault Core is an on-chain transaction firewall for EVM wallets.

It is a non-custodial execution layer that evaluates transactions through policy contracts before execution.

## What problem it solves
Most wallet-security tools only:
- simulate transactions
- warn about risk
- rely on off-chain analysis

Firewall Vault Core takes a different approach:
- safe actions can be allowed
- sensitive actions can be delayed
- dangerous actions can be reverted

This creates a protected wallet flow instead of a simple signing flow.

## Practical protections
Firewall Vault is designed to protect against patterns such as:
- infinite token approvals
- transfers to new or untrusted addresses
- calls to unknown contracts
- large transfers that should not execute instantly

## Core message
**On-chain enforcement, not warnings.**  
**No custody, no backend.**

## High-level architecture

    User
      ↓
    FirewallModule
      ↓
    PolicyRouter
      ↓
    Policies
      ↓
    ALLOW / DELAY / REVERT

More details:
- [`../PROJECT_HOME/ARCHITECTURE.md`](../PROJECT_HOME/ARCHITECTURE.md)

## Core contracts
- `FirewallModule`
- `PolicyRouter`
- `FirewallFactory`

## Policies
- `InfiniteApprovalPolicy`
- `LargeTransferDelayPolicy`
- `NewReceiverDelayPolicy`
- `UnknownContractBlockPolicy`

## Presets
- `0` — Conservative
- `1` — DeFi Trader

## Network
Current MVP deployment:
- Base Mainnet
- `chainId: 8453`

## Security principles
- Non-custodial
- Fully on-chain enforcement
- No backend
- No off-chain policy logic
- No AI
- No key custody

## Quick start

### Requirements
- Node.js
- pnpm
- Foundry

### Install
Run:
- `pnpm install`

### Build contracts
Run:
- `cd packages/contracts`
- `forge build`

### Run tests
Run:
- `cd packages/contracts`
- `forge test -vvv`

## Repository structure
Main contract area:
- `packages/contracts/src`
- `packages/contracts/test`
- `packages/contracts/script`

## MVP scope
- policy-based transaction enforcement
- ETH transaction flow
- delayed transaction queue
- Base-first deployment

## Limitations
- MVP stage
- audit status must be checked separately
- UI lives in a separate repository
- some advanced user features are intentionally out of scope for MVP

## Related repositories
- [`../firewall-ui`](../firewall-ui)
- [`../PROJECT_HOME`](../PROJECT_HOME)

## Documentation
- [`../PROJECT_HOME/README.md`](../PROJECT_HOME/README.md)
- [`../PROJECT_HOME/ARCHITECTURE.md`](../PROJECT_HOME/ARCHITECTURE.md)
- [`../PROJECT_HOME/SECURITY_MODEL.md`](../PROJECT_HOME/SECURITY_MODEL.md)
