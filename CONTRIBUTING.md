# Contributing

This is the public repository for the protocol contracts. Do not add deployment material,
credentials, test tokens, application/backend code, or unpublished product files.

## Before opening a pull request

1. Build the DEX first, then the protocol contracts:

   ```sh
   ./scripts/build.sh
   ```

2. If a public ABI changed, regenerate and commit it:

   ```sh
   node scripts/generate-abis.mjs
   node scripts/generate-abis.mjs --check
   ```

3. Keep compiler settings, remappings, and the pool init-code hash consistent.
   A change that alters the bytecode must be reviewed as a new release, not a
   silent patch.
4. Do not commit `out/`, `cache/`, `.env`, keys, or local paths.
5. Preserve upstream license headers and notices.

## Scope

- Public contracts, tests, ABIs, public docs, and integration examples are in
  scope.
- Deployment scripts, signer material, application backends, and unpublished
  product planning are out of scope.
- Security reports should follow [`SECURITY.md`](SECURITY.md), not a public
  issue.

## Review

Changes to contracts require an independent review. Do not merge a contract
change on the author's approval alone. Release tags are immutable.
