#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../packages/contracts"
forge build
forge test -vvv
