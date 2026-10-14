# finance-crypto v0.1 design

Status: approved and implemented for v0.1; see README and implementation-progress.md for verification and the March 0.5.0 solver limitation.

## Purpose and boundary

Provide a chain-neutral, pure accounting adapter for normalized wallet and
exchange events. Turn exact event amounts into balanced finance-ledger drafts;
retain the event's transaction or exchange reference for audit. Each library
remains usable without the next. finance-crypto depends on finance-ledger and
finance-core, not finance-codec.

Project location: `/Users/80197052/code/finance-crypto`.
Compiler: March 0.5.0, pinned in `.march-version`.
Use Forge, separate responsibility-focused modules, opaque smart constructors,
refinements where applicable, example tests, and generated property tests.

## Approach

Use normalized events rather than RPC payloads or a chain-specific SDK. This
fits the agreed four-library split and permits Bitcoin, EVM, Solana, and exchange
adapters later without embedding their protocols in the accounting kernel.

Alternatives considered:

- EVM-first: faster access to one chain's conventions, but couples the accounting
  model to a protocol and postpones exchange/non-EVM support.
- RPC/signing SDK first: substantially larger security and operational surface,
  outside the agreed event/accounting responsibility.

## Modules

| Module | Responsibility |
| --- | --- |
| CryptoError | Domain errors, wrapping core and ledger errors |
| CryptoIdentity | Opaque network and native/token asset identity |
| CryptoReference | On-chain and exchange event references, deterministic replay metadata |
| CryptoFee | Exact fee specification and balanced fee postings |
| CryptoEvent | Immutable event envelope and balanced event builders |

No mutable registry, actor service, network capability, or ambient clock is
required. Keep posting ownership with finance-ledger.

## Identity

An opaque Network contains two nonempty canonical strings: namespace and network
reference. Reject ASCII whitespace/control characters. Derive a stable identifier
with byte-length-prefixed components; never concatenate unescaped delimiters.
Different networks, including test networks, must remain distinct.

Opaque crypto asset descriptors contain a Network, Native or Token kind, and a
FinanceAsset.Asset. Token descriptors additionally contain a contract/mint string.
Delegate core identity generation to FinanceAsset.native/token using the network's
stable identifier. Preserve the core precision range 0..255. No ticker-based
equality; no inference of decimals from a symbol or contract.

Callers supply canonical network references and contract/mint spellings. The
generic layer does not lowercase arbitrary addresses or promise checksum,
chain-membership, or protocol-format validation. Human-friendly symbols are not
identity. Existing core assets with differently encoded network strings require
an explicit caller mapping; never silently merge them.

## Event references and metadata

An opaque Reference is either:

- OnChain(network, transactionId, eventId), or
- Exchange(venue, accountScope, eventId).

Each component is nonempty and excludes ASCII whitespace/control characters.
eventId is required: a transaction may contain multiple relevant transfers or
fills. Exchange accountScope prevents identical provider IDs from colliding
across accounts. Generic IDs are opaque; no chain-specific case normalization.

Build FinanceMetadata from an explicit source, effective UTC seconds, recorded
UTC seconds, and the reference. Use a library-prefixed, byte-length-prefixed
encoding of the full reference as external_id. Retain the supplied source as
the metadata source. Reuse FinanceMetadata's effective <= recorded invariant.

The reference, supplied timestamps, ordered postings, and event envelope are
immutable. Retries must reuse source, reference, timestamps, and postings.
Changing financial content under a replay key is a ledger conflict. Distinct
event IDs in one transaction must post independently.

Block hash/height, confirmations, finality, pending/mined status, and reorg
observations are not part of v0.1 accounting metadata. They change independently
of a normalized financial event and need a separate ingestion policy. A caller
chooses when an event is eligible for posting. Reorg correction uses a new linked
ledger reversal; no automatic chain monitoring or finality claims.

## Event envelope and posting lifecycle

An opaque Event retains event kind, Reference, FinanceMetadata, and LedgerEntry.Draft.
Public accessors expose immutable values. Builders accept an explicit journal
entry ID; no random IDs or reads of the clock.

Builders check their semantic inputs, construct postings with LedgerEntry.posting,
and return Result(Event, CryptoError.Error). The caller retrieves the draft and
uses LedgerJournal.validate/post_validated or LedgerJournal.post. The destination
journal remains authoritative for account existence, asset declarations, replay
conflicts, and atomic append. No crypto API constructs a PostedEntry or mutates
an already posted entry.

Keep the envelope alongside the returned posted entry in caller-owned storage.
The ledger stores its draft metadata/reference key, not the entire crypto envelope.
Cross-envelope persistence and atomicity are the caller's responsibility.

## Accounting operations

All quantities are existing FinanceAmount.Quantity values with strictly positive
atoms; zero/negative amounts are rejected. Asset identity AND precision must
match the declared accounts. Builders take account values rather than untyped
account names so they can reject obvious mistakes before posting. The ledger
still validates those definitions against its actual chart.

### Transfers, deposits, withdrawals

These share a two-leg primitive: debit destination and credit source in exactly
the same asset/precision. Reject equal source/destination account IDs. Deposit
and withdrawal name the event's direction relative to the caller's wallet or
exchange custody; their counterpart is an explicit caller-supplied clearing
account, not synthesized income or expense.

Wallet and exchange custody accounts use AssetAccount. Clearing counterparties
may use other classifications according to the caller's chart. The library does
not introduce a new ledger classification for exchange location. Transfer is
between two AssetAccount custody accounts. Deposit requires an AssetAccount
destination; withdrawal requires an AssetAccount source.

On-chain principal operations take a CryptoIdentity asset descriptor and reject
quantity/network mismatch with the Reference. Exchange events may use any core
asset, including fiat; their custody location is represented by accounts and the
exchange reference, not a fabricated chain identity.

### Trades

Accept explicit buy quantity, sell quantity, receive/pay custody accounts, and
one clearing account for each asset. Reject identical buy/sell assets (including
precision). Debit received custody and credit its clearing account; credit paid
custody and debit its clearing account. Each pair balances independently.

No implied price, floating point conversion, fiat valuation, cost basis, realized
gain, or tax treatment. Require the caller to supply both exact trade legs.
For on-chain trades, supplied crypto descriptors must belong to the reference
network. Exchange trades may include fiat legs.

### Fees and gas

An opaque Fee specifies positive exact quantity, funding account, and expense
account. Funding must be AssetAccount and expense must be ExpenseAccount; both
must declare the fee's asset and precision, with distinct IDs.

An optional fee adds debit expense and credit funding to the same event draft,
atomically with the principal postings. None means no fee: do not emit zero
postings. Fees may use a different asset from the principal.

On-chain gas requires a native crypto asset descriptor on the reference network;
reject token gas in this v0.1 model. Model sponsored/non-native fee systems later
through an explicit extension rather than mislabeling token charges as gas.
Exchange fees may use any core asset and are not labeled gas. An on-chain
token-denominated service fee is a generic fee, not gas, and must match the
reference network when supplied as a crypto descriptor.

Provide a standalone fee-only event for failed transactions that still incur
gas and exchange fee adjustments; do not record successful principal legs for
a failed transaction. Failure classification is caller-supplied, not inferred
from external transaction data.

Fees are additional gross debits from funding. Builders never subtract them
from the principal implicitly. For a withdrawal of 10 with fee 1, source loses
11, destination receives 10, expense increases 1. For a trade, both quoted legs
are gross; fee postings remain separate. Reject aliasing of trade clearing and
custody accounts for the same leg to prevent silently cancelling a trade leg.

## Errors and guarantees

Domain errors distinguish invalid identifiers, account roles, account aliasing,
asset mismatch, network mismatch, invalid amount, and invalid gas asset.
Preserve wrapped core/ledger errors rather than panicking on caller input.

Constructors cannot be forged externally. A valid Event is a financial draft,
not proof of network validity, sufficient funds, chain finality, ownership,
authorization, or a successful ledger post. Negative projected balances are
allowed by the underlying ledger; overdraft policies are outside this library.

## Acceptance tests

- Network/token identities are collision resistant under separator-containing
  components and distinguish networks and contracts/mints; precision boundaries
  are enforced. Byte-length encoding is deterministic for Unicode components.
- Transaction events sharing a transaction ID but differing event IDs have
  distinct keys; exchange venue/account scopes remain independent.
- Deposit/withdrawal/transfer produce literal expected balances and reject wrong
  account roles, aliases, zero/negative amounts, mismatched assets/precision.
- Trades produce four balanced legs; no cross-asset atom netting, including
  fiat/crypto exchange trades and same ticker on different networks.
- Gas and fees post to expense/funding in their own asset; fee-only failed
  transactions have no principal movement. Reject wrong-network and token gas.
- Fees are additional, not implicitly netted; hand-checked fixtures pin totals.
- Same event retries do not increase journal length; changed amounts conflict;
  distinct event IDs post independently; caller timestamps stay stable.
- Reversing an event's posted entry restores all principal and fee balances
  without altering the original event or historical journal.
- Generated positive amounts preserve per-asset conservation for operations,
  fees and reversals. Use multiple deterministic seeds in debug and release.
- Compile-time fixtures reject forged opaque identity/reference/fee/event values
  and invalid refinement literals, with a positive control for module discovery.
- Run finance-core and finance-ledger regression suites on March 0.5.0.

## Out of scope

RPC, signing/private keys, live ingestion, address checksum libraries, token
registries, automatic chain decimal discovery, NFT-specific units, UTXO selection,
bridges and cross-chain transfers, swaps with partial fills inferred from logs,
transaction replacement tracking, automated reorg handling, pricing, valuation,
tax lots, durable storage, actor services, and JSON/CSV codecs. Those are separate
adapters or later libraries, not prerequisites for this accounting release.
