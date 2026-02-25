# 🔐 FIREWALL VAULT — PROJECT CONTEXT

## 1. Vision

Firewall Vault is a non-custodial, on-chain Transaction Firewall for EVM networks.

It is not:
- analytics
- warnings
- browser extension filtering
- monitoring bot
- custodial wallet

It is:
- hard on-chain enforcement
- transaction blocking
- delay mechanism
- deterministic execution layer
- protected smart-account wallet

Goal:
Create a protected version of a user's wallet that prevents drain attacks and dangerous approvals — while remaining usable in real DeFi workflows.

---

## 2. Strategic Model

The product consists of three layers:

### Layer 1 — Core (Open Source, Immutable)

Fully open-source and trust-minimized:

- FirewallModule
- PolicyRouter
- Policies
- Factory

Core must:
- Be immutable
- Have no upgradeability
- Have no proxy pattern
- Contain no monetization logic
- Contain no subscription checks
- Be fully non-custodial
- Require no off-chain services

Core is the trust foundation of the product.

---

### Layer 2 — Preset System

Presets are predefined policy configurations.

Preset =:
- set of policies
- configuration parameters
- delay thresholds
- protection level

Presets may be:
- Basic (free)
- Advanced (SaaS UI controlled)

Presets must be compatible with Factory initialization.

---

### Layer 3 — SaaS Layer (Monetization)

Monetization is NOT inside contracts.

Revenue comes from:
- Advanced UX
- Preset management
- Automation layer
- Multi-wallet dashboard
- Advanced profiles
- Enterprise/team mode
- Risk visualization
- Transaction management UX

Core remains free and open.

---

## 3. Architecture

User
  ↓
FirewallModule (Wallet Contract)
  ↓
PolicyRouter
  ↓
Policies
  ↓
Decision: Allow / Delay / Revert

Each user has their own wallet contract.

One user = one deployed contract.

No shared custody model.

---

## 4. Factory Strategy

MVP Factory (v1):
- Deploys new FirewallModule
- Calls init(router, owner, recovery, presetConfig)
- Emits WalletCreated event
- Has immutable router reference

No:
- Admin control over deployed wallets
- Upgrade functionality
- Hidden owner powers

Future plan:
Factory may switch from direct deploy to minimal proxy clones (EIP-1167),
BUT:
- External API must remain identical
- WalletCreated event format must remain identical
- UI must not break

---

## 5. MVP Definition

MVP includes:

- FirewallModule (immutable)
- PolicyRouter
- 3–4 core policies
- Factory (deploy version)
- 3 protection presets
- Minimal Web UI:
  - Create protected wallet
  - Choose preset
  - Execute transaction
  - View delayed transactions
  - Execute/cancel delayed tx

MVP is free.

---

## 6. Explicit Non-Goals (MVP)

- No proxy upgradeability
- No subscription logic in contracts
- No pay-per-transaction logic
- No on-chain fee extraction
- No multi-sig
- No DAO mode
- No ML/AI risk scoring
- No external dependency for decision making

---

## 7. Security & Trust Requirements

Must include:

- Open-source repository
- Transparent commit history
- Verified contracts on Base
- Reproducible deployments
- Threat model documentation
- Clear explanation of:
  - What is protected
  - What is NOT protected

Future:
- Public audit
- Community review

---

## 8. 6-Month Roadmap

Phase 1 (0–2 months after launch):
- Core freeze
- UI launch
- Documentation
- Security explanation
- Feedback loop

Phase 2 (2–4 months):
- UX improvements
- Gas optimizations
- More presets
- Automation layer (SaaS start)

Phase 3 (4–6 months):
- Pro profiles
- Multi-wallet dashboard
- Team mode
- Enterprise offering
- Possible expansion to other L2 networks

---

## 9. Engineering Rules

- Minimalism over complexity
- Deterministic behavior
- No magic logic
- No hidden trust assumptions
- Small diffs
- Clear events
- Strong test coverage

Codex must:
- Propose plan before changes
- Modify only relevant files
- Never touch artifacts (out, cache, broadcast)
- Never introduce upgradeability without explicit request

---

This document defines the direction of Firewall Vault development.
