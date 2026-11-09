#!/usr/bin/env node
// Generate the public ABI set from the staged Foundry build artifacts.
// Usage:
//   node scripts/generate-abis.mjs
//   node scripts/generate-abis.mjs --check
//
// The script has no third-party dependencies. It only reads the public
// contracts listed below; internal contracts and test artifacts are excluded.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const ROOT = new URL("..", import.meta.url).pathname;
const ABI_DIR = join(ROOT, "abi");

const CONTRACTS = [
  { name: "AgenticToken", project: "root" },
  { name: "AgenticTokenFactory", project: "root" },
  { name: "AgenticPolicy", project: "root" },
  { name: "AgenticPolicyRegistry", project: "root" },
  { name: "AgenticAssetRegistry", project: "root" },
  { name: "AgenticQuoteAssetRegistry", project: "root" },
  { name: "AgenticVenueRegistry", project: "root" },
  { name: "AgenticIdentityRegistry", project: "root" },
  { name: "AgenticIdAdapter", project: "root" },
  { name: "AgenticTreasury", project: "root" },
  { name: "AgenticFacilityFactoryV2", project: "root" },
  { name: "AgenticFacilityBase", project: "root" },
  { name: "AgenticVaultFacility", project: "root" },
  { name: "AgenticLaunchFacility", project: "root" },
  { name: "AgenticLockerFacility", project: "root" },
  { name: "AgenticGameFacility", project: "root" },
  { name: "AgenticEscrowFacilityV2", project: "root" },
  { name: "AgenticNFT", project: "root" },
  { name: "AgenticNFTFactory", project: "root" },
  { name: "AgenticNFTRegistry", project: "root" },
  { name: "AgenticNFTFacilityBase", project: "root" },
  { name: "AgenticNFTVaultFacility", project: "root" },
  { name: "AgenticNFTLaunchFacility", project: "root" },
  { name: "AgenticNFTLockerFacility", project: "root" },
  { name: "AgenticNFTGameFacility", project: "root" },
  { name: "AgenticNFTEscrowFacility", project: "root" },
  { name: "AgenticNFTFacilityFactory", project: "root" },
  { name: "Agentmarket", project: "root" },
  { name: "AgentswapPoolFactory", project: "root" },
  { name: "AgentswapV3Factory", project: "dex" },
  { name: "AgentswapPositionManager", project: "dex" },
  { name: "AgentswapRouter", project: "dex" },
  { name: "AgentswapQuoter", project: "dex" },
  { name: "UniswapV3Pool", project: "dex" }
];

function artifactPath(project, name) {
  return project === "dex"
    ? join(ROOT, "dex", "out", `${name}.sol`, `${name}.json`)
    : join(ROOT, "out", `${name}.sol`, `${name}.json`);
}

function generated() {
  const result = new Map();
  for (const { name, project } of CONTRACTS) {
    const path = artifactPath(project, name);
    if (!existsSync(path)) {
      throw new Error(`missing artifact: ${path}`);
    }
    const artifact = JSON.parse(readFileSync(path, "utf8"));
    if (!Array.isArray(artifact.abi)) {
      throw new Error(`artifact has no ABI array: ${path}`);
    }
    const body = `${JSON.stringify(artifact.abi, null, 2)}\n`;
    result.set(`${name}.json`, body);
  }
  const manifest = {
    schemaVersion: 1,
    generatedBy: "scripts/generate-abis.mjs",
    contracts: CONTRACTS.map(({ name, project }) => ({
      name,
      project,
      abi: `${name}.json`
    }))
  };
  result.set("index.json", `${JSON.stringify(manifest, null, 2)}\n`);
  return result;
}

function hash(value) {
  return createHash("sha256").update(value).digest("hex");
}

const check = process.argv.includes("--check");
const files = generated();
let failed = false;

mkdirSync(ABI_DIR, { recursive: true });

for (const [file, body] of files) {
  const path = join(ABI_DIR, file);
  if (check) {
    if (!existsSync(path)) {
      console.error(`missing ABI: ${file}`);
      failed = true;
      continue;
    }
    const current = readFileSync(path, "utf8");
    if (current !== body) {
      console.error(`stale ABI: ${file} (${hash(current)} != ${hash(body)})`);
      failed = true;
    }
  } else {
    writeFileSync(path, body);
    console.log(`wrote abi/${file}`);
  }
}

if (check) {
  const expectedNames = new Set(files.keys());
  const actualNames = readdirSync(ABI_DIR).filter((file) => file.endsWith(".json"));
  const extra = actualNames.filter((file) => !expectedNames.has(file));
  if (extra.length > 0) {
    console.error(`unexpected ABI files: ${extra.join(", ")}`);
    failed = true;
  }
}

if (check && failed) process.exit(1);
if (check) console.log(`ABI check passed: ${files.size} files`);
