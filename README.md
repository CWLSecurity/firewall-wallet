# Firewall Vault Core

**Protected version of your wallet**

Firewall Vault Core is the on-chain enforcement layer behind Firewall Vault.

It is a non-custodial transaction firewall for EVM wallets.  
Instead of merely warning users about risk, it evaluates transactions through policy contracts before execution.

## What it does
Firewall Vault Core can:
- allow a transaction
- delay a transaction
- revert a transaction

This creates a protected wallet flow instead of a simple signing flow.

## Core architecture
Main contracts:
- `FirewallModule`
- `PolicyRouter`
- `FirewallFactory`

Policies:
- `InfiniteApprovalPolicy`
- `LargeTransferDelayPolicy`
- `NewReceiverDelayPolicy`
- `UnknownContractBlockPolicy`

## Execution model
Transaction flow:

`User -> FirewallModule -> PolicyRouter -> Policies -> Allow / Delay / Revert`

## Network
Current MVP deployment:
- Base Mainnet
- `chainId: 8453`

## Presets
- `0` — Conservative
- `1` — DeFi Trader

## MVP scope
- Policy-based transaction enforcement
- ETH transaction flow
- Delayed transaction queue
- Base-first deployment

## Security principles
- Non-custodial
- Fully on-chain enforcement
- No backend
- No off-chain policy logic
- No AI
- No key custody

## Limitations
- MVP stage
- Audit status must be checked separately
- UI and launch docs live in separate repositories
- Some advanced user features are intentionally out of scope for MVP

## Related repositories
- `../firewall-ui`
- `../PROJECT_HOME`

## Core message
**On-chain enforcement, not warnings.**  
**No custody, no backend.**
