# Codex rules for firewall-wallet

## Never touch generated artifacts
Do not edit, create, delete, or move anything in:
- packages/contracts/out/**
- packages/contracts/cache/**
- packages/contracts/broadcast/**
- packages/contracts/deployments/**

## Never touch secrets
- .env
- .env.*
- packages/contracts/.env*

## Allowed areas
- packages/contracts/src/**
- packages/contracts/test/**
- packages/contracts/script/**
- README.md / docs/** (if asked)

## Workflow (strict)
1) Propose a short plan first.
2) Make minimal changes only.
3) After changes, list exact files changed.
4) Do not run commands; I will run:
   - git diff
   - forge test -vvv
5) No refactors unless explicitly requested.
