#!/usr/bin/env node
// Verify that PoolAddress.POOL_INIT_CODE_HASH matches the staged UniswapV3Pool
// creation code. Requires Foundry's `cast` on PATH.

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const ROOT = new URL("..", import.meta.url).pathname;
const artifactPath = join(
  ROOT,
  "dex",
  "out",
  "UniswapV3Pool.sol",
  "UniswapV3Pool.json"
);
const poolAddressPath = join(
  ROOT,
  "dex",
  "contracts",
  "libraries",
  "PoolAddress.sol"
);

const artifact = JSON.parse(readFileSync(artifactPath, "utf8"));
const creationCode = artifact.bytecode?.object;
if (!creationCode || creationCode === "0x") {
  throw new Error(`missing creation code: ${artifactPath}`);
}

const actual = execFileSync("cast", ["keccak", creationCode], {
  encoding: "utf8"
}).trim();

const source = readFileSync(poolAddressPath, "utf8");
const match = source.match(/POOL_INIT_CODE_HASH = (0x[0-9a-fA-F]{64})/);
if (!match) {
  throw new Error("POOL_INIT_CODE_HASH not found");
}
const expected = match[1].toLowerCase();

if (actual.toLowerCase() !== expected) {
  console.error("pool init-code hash mismatch");
  console.error(`expected: ${expected}`);
  console.error(`actual:   ${actual}`);
  process.exit(1);
}

console.log(`pool init-code hash OK: ${actual}`);
