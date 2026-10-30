# Examples

Minimal TypeScript integration skeletons. They are illustrative, not a
production wallet or signing service.

```sh
npm install viem tsx
```

Use your own wallet client with a signer. Do not commit private keys, mnemonics,
or API keys. Replace placeholder addresses and values before running anything.

- [`facility-create.ts`](facility-create.ts) — create a `LAUNCH` facility.
- [`token-and-pool.ts`](token-and-pool.ts) — create a gated token and its first
  gated pool.

The exact factory ABIs are in [`../abi/`](../abi/), and mainnet addresses are in
[`../deployments/56.json`](../deployments/56.json).
