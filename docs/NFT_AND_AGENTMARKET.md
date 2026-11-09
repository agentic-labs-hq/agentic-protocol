# NFT and Agentmarket

This page covers the NFT standard, NFT facilities, and Agentmarket on BSC
mainnet (chain 56).

## Addresses

| Contract | Address |
| --- | --- |
| AgenticNFTRegistry | `0x5B2e805B276D9d756f5CacF58a4599eeCc8e3550` |
| AgenticNFTFactory | `0x9902405C5Ca9800AFE031af837C442a0F2aCaD62` |
| AgenticNFTFacilityFactory | `0x2039D7d5BcB015B64d35Bc65cBa26E3D8FD41615` |
| Agentmarket | `0x4e2aCC31a1dE4cA5DfeeD43956c607e46dd66982` |

Governance is the protocol Safe. The market fee is 100 bps, capped at 500 bps.

## NFT standard

`AgenticNFT` is an ERC-721 collection with a protocol transfer policy.

- Fixed `maxSupply`, set at collection creation. There is no post-deployment
  supply increase.
- The immutable `creator` mints. Others cannot mint.
- `mint(address to, uint256 count)` and
  `mintBatch(address[] recipients, uint256[] counts)` respect the remaining
  supply.
- Every mint and transfer calls the collection's `policy`. Under the canonical
  policy, a transfer to a wallet without a valid Agent ID, or to an ineligible
  facility, reverts. A collection created with another policy follows that
  policy; read `policy()` and the policy registry before assuming eligibility
  rules.
- No burn, pause, admin transfer, proxy, or upgrade. The policy address is
  immutable.
- Metadata uses one of two immutable modes: `baseURI + tokenId`, or an immutable
  `metadataResolver`. The resolver address cannot change; the resolver owner can
  change the content it returns.

### Create a collection

`AgenticNFTFactory.createCollection`:

```text
createCollection(
  string name,
  string symbol,
  address policy,
  uint256 maxSupply,
  string baseURI,
  string metadataURI,
  address metadataResolver
) returns (address nft)
```

- `policy = address(0)` uses the policy registry's current policy.
- `maxSupply` must be greater than zero.
- Set either `baseURI` or `metadataResolver`. With a resolver, `baseURI` may be
  empty. A `policy` of zero uses the policy registry's current policy, called the
  canonical policy in this page.
- The factory registers the collection in `AgenticNFTRegistry` and emits
  `CollectionCreated`.

The transaction does not return the new collection address. Read it from the
`CollectionCreated` event in the receipt. A static call can compute the predicted
address, but it does not persist the collection.

### Read a collection

```solidity
name() symbol() creator() policy() factory()
maxSupply() totalMinted()
baseURI() metadataURI() metadataResolver()
tokenURI(uint256) ownerOf(uint256)
```

`INFTRegistry`:

```solidity
isRegistered(address collection) returns (bool)
policyOf(address collection) returns (address)
creatorOf(address collection) returns (address)
```

## NFT facilities

Five facility types extend the existing venue registry:

| Type | Category | Purpose |
| --- | --- | --- |
| `NFT_VAULT` | CUSTODY | Project NFT treasury |
| `NFT_LAUNCH` | CUSTODY | Primary sale custody |
| `NFT_LOCKER` | CUSTODY | Time-locked NFT lock |
| `NFT_GAME` | PURPOSE | Game asset custody and consumption |
| `NFT_ESCROW` | PURPOSE | Role-controlled NFT escrow |

Create one with `AgenticNFTFacilityFactory.createFacility(bytes32 kind, bytes initData)`.
The factory is registered as a CUSTODY and PURPOSE registrar in the venue
registry. The created facility is registered with the matching category.

`kind` is the bytes32 constant in `Types.sol`. `initData` layouts:

| Kind | `initData` |
| --- | --- |
| `NFT_VAULT` | `abi.encode(address owner)` |
| `NFT_LAUNCH` | `abi.encode(address owner, address operator, address beneficiary)` |
| `NFT_LOCKER` | `abi.encode(address owner, address beneficiary, uint64 unlockTime)` |
| `NFT_GAME` | `abi.encode(address owner, address operator)` |
| `NFT_ESCROW` | `abi.encode(address owner, address arbiter, address beneficiary)` |

`owner` is required. `unlockTime` is a Unix timestamp in seconds. Optional roles
may be zero and set later, except the LOCKER beneficiary, which is required and
must be an agent. A non-zero beneficiary must be an agent, not a facility. The FT initData layouts in
[`FACILITY_GUIDE.md`](FACILITY_GUIDE.md) do not apply to NFT kinds. See
[`abi/AgenticNFTFacilityFactory.json`](../abi/AgenticNFTFacilityFactory.json).

Funding rules:

- Under the canonical policy, CUSTODY facilities receive NFTs only by minting
  directly to the facility. They have no public NFT deposit function.
- Under the canonical policy, PURPOSE facilities receive NFTs by agent
  transfer.
- Outflows use `transferFrom`; the receiver does not need to implement
  `onERC721Received`.

Facility lifecycle for gated collections under the canonical policy:

| Facility | Enter | Exit | Caller | Recipient | Limits |
| --- | --- | --- | --- | --- | --- |
| `NFT_VAULT` | Mint to the facility | `release(collection, tokenId, to)` | Owner | Agent or migration target | No public deposit; no time gate |
| `NFT_LAUNCH` | Mint to the facility | `release(collection, tokenId, to)` | Operator | Agent or migration target; after `close`, only beneficiary or migration target | `close` by owner or operator; beneficiary must be set before close |
| `NFT_LOCKER` | Mint to the facility | `unlock(collection, tokenId, to)` | Anyone after `unlockTime` | Beneficiary or migration target | `setBeneficiary` and `extend` are owner-only before unlock; no changes after |
| `NFT_GAME` | Agent transfer | `release` / `refund`; `consume` | Operator | Agent or migration target | `consume` is permanent; consumed tokens cannot be released, refunded, or migrated |
| `NFT_ESCROW` | Agent transfer | `release`; `refund` | Beneficiary or arbiter for release; arbiter for refund | Agent or migration target | Owner sets roles; no depositor record |

The [facility guide](FACILITY_GUIDE.md) shares the factory and migration concepts,
but its FT function names and `amount` parameters do not apply to NFT kinds.

### Migration

1. Create the replacement with `AgenticNFTFacilityFactory.createFacility`.
2. Governance calls `venueRegistry.revokeFacility(oldFacility)`.
3. The facility owner calls `venueRegistry.setReplacement(oldFacility,
   replacement)`. For CUSTODY and PURPOSE facilities, governance cannot choose
   the replacement; only the facility owner can.
4. The owner calls `migrate(replacement)`. This records the target and does not
   move NFTs. The facility must already be revoked, and the replacement must be
   active and match the category and type.
5. The owner calls `migrateTokens(collection, tokenIds)` in chunks. Every token
   must be held by the facility; each is sent to the replacement.
6. `NFT_LOCKER` can migrate only after `unlockTime`. `NFT_GAME` reverts for
   consumed tokens. The other templates have no extra time gate.

## Agentmarket

Agentmarket is a non-custodial, approval-based peer-to-peer NFT market.

- Listings are keyed by `(collection, tokenId)`. A new listing replaces the old
  one for that token.
- Payment is native BNB only. The seller sets the price.
- The market has no custody path. A normal listing and `buy` never leave the
  NFT or the payment in the contract. `buy` transfers the NFT from the seller
  to the buyer and pays the seller and the protocol treasury in the same
  transaction. Forced transfers are not recoverable.
- Fee is snapshotted when the seller lists. The treasury is read at settlement.
  At 100 bps (1%), a 0.5 BNB listing pays a 0.005 BNB fee; the seller receives
  0.495 BNB. The buyer pays 0.5 BNB plus gas. 500 bps is 5%. A later fee change
  does not alter an existing listing.
- No pause, upgrade, bids, royalties, or ERC-20 payments.

### List, cancel, buy

```text
list(address collection, uint256 tokenId, uint256 price, uint64 deadline)
cancel(address collection, uint256 tokenId)
buy(address collection, uint256 tokenId) payable
```

- `price` and the `buy` value are in wei. `0.5 BNB = 500000000000000000 wei`.
- `deadline` is a Unix timestamp in seconds; `deadline = 0` means no expiry.
- The seller must own the token and approve Agentmarket.
- `buy` must send exactly the current listing price. A different value reverts.
- The seller cannot buy its own listing.
- Read `isExecutable(collection, tokenId)` and
  `listingOf(collection, tokenId)` before buying.

### Listing semantics

A listing is a standing order, not a hold on the token.

- Transferring the NFT away does not cancel the listing.
- Revoking approval does not cancel the listing.
- `approve-all` survives NFT transfers. A single-token `approve` is cleared by a
  transfer.
- If the token returns to the seller and the market is still approved, the old
  listing can execute again.
- Only `cancel` cancels a listing.

A preview or quote is not an order lock. `buy` executes against the listing that
is current at settlement. A same-price cancel and re-list can be filled by an
older transaction; a price change makes the old transaction revert.

### Events

- NFT: `CollectionCreated`, `Minted`, ERC-721 `Transfer`.
- Market: `Listed`, `Cancelled`, `Sold` (includes the fee recipient).

## Security boundaries

- Cross-type mis-send is a user risk. The protocol does not whitelist receiver
  types. A creator can mint an NFT into a facility that cannot transfer NFTs;
  the token can become stuck.
- `NFT_ESCROW` is role-controlled: the beneficiary or arbiter releases, the
  arbiter refunds, and the owner sets the roles. It does not record a depositor.
- The metadata resolver address is immutable, but its content is not.
- A treasury that rejects BNB makes `buy` revert. Fees continue to go to the old
  treasury until governance changes it.
- Do not send assets to canonical facility instances that are not registered in
  the venue registry.

## ABIs and examples

Generated ABIs are in [`abi/`](../abi/):

- `AgenticNFT.json`
- `AgenticNFTFactory.json`
- `AgenticNFTRegistry.json`
- `AgenticNFTVaultFacility.json`
- `AgenticNFTLaunchFacility.json`
- `AgenticNFTLockerFacility.json`
- `AgenticNFTGameFacility.json`
- `AgenticNFTEscrowFacility.json`
- `AgenticNFTFacilityFactory.json`
- `Agentmarket.json`

The [Agentmarket CLI](https://github.com/agentic-labs-hq/agentmarket-cli)
provides wallet-safe preview and execute commands for collection creation,
minting, approvals, listings, and buys.
