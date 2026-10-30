#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# DEX first: the protocol cross-version tests read dex/out artifacts.
(
  cd dex
  forge build
  forge test
)

node scripts/check-pool-hash.mjs

forge build
forge test

node scripts/generate-abis.mjs --check
