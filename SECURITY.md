# Security

## Reporting

Report suspected vulnerabilities privately. Prefer GitHub private vulnerability
reporting when it is enabled for this repository. If it is not available, email
`agentswap@proton.me`.

Do not open a public issue for an exploitable finding.

Include:

- affected chain and contract address;
- affected function or component;
- impact and prerequisites;
- reproduction steps or a minimal proof of concept;
- whether funds are at risk.

## Scope

The deployed contracts listed in `deployments/56.json` are in scope. Test
contracts, mocks, and build scripts in this repository are not deployed
production contracts.

This repository does not contain private keys, Safe signer material, or
deployment credentials. Do not send secrets in a report.

No bug bounty or response-time commitment is made by this document.
