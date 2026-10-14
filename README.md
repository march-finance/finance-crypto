# finance-crypto

[![Tests](https://github.com/march-finance/finance-crypto/actions/workflows/ci.yml/badge.svg)](https://github.com/march-finance/finance-crypto/actions/workflows/ci.yml)

Licensed under the [MIT License](LICENSE).

## GitHub checkout and CI

Clone the repositories into the same parent directory so Forge's sibling path
dependencies resolve (finance-crypto is test-only for finance-codec integration):

```sh
git clone https://github.com/march-finance/finance-core.git
git clone https://github.com/march-finance/finance-ledger.git
git clone https://github.com/march-finance/finance-crypto.git
cd finance-crypto
forge test --seed=42
```

GitHub Actions runs on pushes, pull requests and manual dispatches. It installs
the pinned March 0.5.0 release, checks/builds this package, and runs debug/release
tests and properties. Dependencies are checked out from their `main` branches.
Compile-time contract checks run with Z3.

Exact, chain-neutral accounting for normalized wallet and exchange events in
March. Produces immutable, balanced **drafts**, not blockchain transactions.
Version 0.1.0; March 0.5.0 is pinned in `.march-version`.

## Setup

Keep this package beside `finance-core` and `finance-ledger`, as specified by its
local Forge path dependencies. Run `forge toolchain install v0.5.0` if needed;
`forge toolchain which` confirms the resolved compiler. No RPC, network account,
API key, wallet secret, clock capability, or registry is needed.

| Module | Main operations |
| --- | --- |
| CryptoIdentity | `network`, `native`, `token`, `amount`, `exchange_amount` |
| CryptoReference | `on_chain`, `exchange`, `key`, `metadata` |
| CryptoFee | `make`, `postings`, reference/account checks |
| CryptoEvent | `context`, `transfer`, `deposit`, `withdrawal`, `trade`, `fee_only` |
| CryptoError | Domain errors and wrapped `Core` / `Ledger` errors |

All fallible operations return `Result(_, CryptoError.Error)`. Account and
journal construction/posting are finance-ledger operations returning its error
type. Use `Result.map_err(result, fn e -> CryptoError.Ledger(e))` when composing
them in a crypto-Result function.

## Identity and exact amounts

`network(namespace, reference)` identifies a network, including its environment.
`native(network, precision)` and `token(network, contractOrMint, precision)` create
opaque descriptors and corresponding core assets. Components are byte-length
prefixed; namespace, network, contract/mint, and caller spelling all matter.
Precision must be 0..255. Accessors include `core_asset`, `asset_network`,
`asset_kind`, `contract`, and refined `precision`.

Callers must canonicalize identifiers. This generic library rejects empty IDs,
ASCII control characters, ASCII whitespace, and DEL, but does not validate a
chain's address format, checksum, contract existence, or decimals. It does not
lowercase addresses. Symbols/tickers are not asset identities. Legacy core assets
using other network encodings need explicit mapping; they are not silently merged.

Use `amount(descriptor, quantity)` for on-chain provenance. Identity AND precision
must agree, and atoms must be strictly positive. `exchange_amount(quantity)` also
requires positive atoms, permits fiat, and has no chain descriptor; it cannot be
used for an on-chain event. Quantities remain core BigInt atom quantities—no Float
conversion. `quantity(amount)` exposes the original exact value.

## Token transfer with native gas

This block belongs inside a Result-returning function after constructing the
accounts. It is the same flow covered by the token/native integration tests:

```march
let? ctx = CryptoEvent.context("transfer-1", ref, "wallet-import", 100, 101)
let? principal = CryptoIdentity.amount(token, token_quantity)
let? gas_amount = CryptoIdentity.amount(native, gas_quantity)
let? gas = CryptoFee.make(CryptoFee.Gas, gas_amount, gas_wallet, gas_expense)
let? event = CryptoEvent.transfer(ctx, principal, token_wallet, recipient, Some(gas))
let? validated = Result.map_err(
  LedgerJournal.validate(journal, CryptoEvent.draft(event)),
  fn e -> CryptoError.Ledger(e))
Result.map_err(LedgerJournal.post_validated(journal, validated),
  fn e -> CryptoError.Ledger(e))
```

Here `ref` comes from `CryptoReference.on_chain(network, transactionId, eventId)`;
`native` and `token` are descriptors on that network. Token wallet/recipient
accounts declare the token asset, gas wallet/expense declare the native asset.
Wallets are `LedgerAccount.AssetAccount`; gas expense is `ExpenseAccount`.
With 10 token atoms and 1 gas atom, the token wallet loses 10, recipient gains
10, gas wallet loses 1, and gas expense gains 1. Each asset balances separately.

No fee is `None`, not a zero-amount Fee. Gas must be native to the reference
network. Token service charges use `ServiceFee` with a matching network descriptor,
not `Gas`. Exchange events reject Gas but accept ServiceFee in any core asset.

## Operations and account roles

- `transfer(ctx, amount, source, destination, fee)` requires two AssetAccounts.
- `deposit(ctx, amount, counterparty, custody, fee)` requires AssetAccount custody.
- `withdrawal(ctx, amount, custody, counterparty, fee)` requires AssetAccount custody.
- `trade(ctx, buy, sell, receive, pay, buyClearing, sellClearing, fee)` requires
  AssetAccount receive/pay and distinct buy/sell assets.
- `fee_only(ctx, fee)` records just the expense/funding pair, suitable for gas on
  a failed transaction or an exchange fee adjustment.

Counterparties and clearing accounts are explicit; the library does not assume
deposits are income or withdrawals are expenses. An exchange is a custody location
using AssetAccount, not a new ledger classification. Fee funding is AssetAccount;
fee expense is ExpenseAccount. Different assets require different accounts.

Builders reject same-ID transfer endpoints, same-leg trade custody/clearing
aliases, account/quantity identity or precision mismatches, and inconsistent
definitions for a repeated account ID. Reusing a consistently defined custody
account as fee funding is supported.

Fees are **additional gross movements**, never implicitly deducted from principal.
Withdraw 10 with fee 1 from the same wallet: wallet -11, counterparty +10, expense
+1. Builders neither infer sufficient funds nor forbid negative ledger balances.

## Exchange trade example

Create the reference with `CryptoReference.exchange("venue", "account-scope", "fill-id")`
and a Context with `CryptoEvent.context`. For buying 2 token atoms for 600 USD
atoms, use `CryptoIdentity.amount(token, tokenQty)` as buy and
`CryptoIdentity.exchange_amount(usdQty)` as sell:

```march
let? event = CryptoEvent.trade(ctx, buy, sell,
  token_custody, usd_custody, token_clearing, usd_clearing, Some(fee))
Result.map_err(LedgerJournal.post(journal, CryptoEvent.draft(event)),
  fn e -> CryptoError.Ledger(e))
```

With a 1 USD-atom ServiceFee funded by USD custody, resulting balances are:

| Account | Atoms |
| --- | ---: |
| Token custody | +2 |
| Token clearing | -2 |
| USD custody | -601 |
| USD clearing | +600 |
| Fee expense (USD) | +1 |

Both gross legs are supplied explicitly. There is no implied price, valuation,
tax basis, gain calculation, or cross-asset netting. On-chain trades require both
descriptors on the transaction network; exchange trades can include fiat.

## Replay, audit, and posting

On-chain references require a transaction ID AND event ID: multiple relevant
events can share one transaction. Exchange keys include venue AND account scope.
The versioned reference key becomes `FinanceMetadata.external_id`; source remains
caller supplied. Reference components are opaque strings, not protocol parsers.

Keep source, reference, effective/recorded UTC seconds, and ordered financial
postings stable across retries. The ledger's source-scoped external key prevents
duplicates; changed financial content conflicts. A new draft ID may resolve to
the original posted ID. Event kind/fee label is descriptive envelope information,
not a second ledger uniqueness namespace: identical financial drafts with the
same reference are the same event. Distinct events require distinct event IDs.

Event builders do not post. Use `CryptoEvent.draft(event)` with the explicit
ledger lifecycle or atomic `LedgerJournal.post`. The destination journal remains
authoritative for its actual account chart and replay state. A successful builder
does not guarantee that a post will succeed.

Persist the immutable envelope alongside the returned PostedEntry yourself.
The journal retains draft metadata/reference key, not the whole crypto envelope.
Neither cross-envelope persistence nor concurrent-writer coordination is provided.
Corrections use `LedgerJournal.reverse` with fresh metadata/ID, retaining the
original entry. Finality, block observations and reorg policy belong to ingestion;
the library never decides when a transaction is eligible to post.

## Verification and limits

```sh
forge check
forge build --release
forge test --seed=42
forge test --seed=123
forge test --release --seed=20261014
sh scripts/check-contracts.sh
```

Tests cover exact balances, account/network/precision rejection, gross fees,
trade clearing, failed-transaction fee-only events, replay and reversals, plus
generated conservation properties. Compile-time fixtures reject forged opaque
values and invalid inherited precision refinements, after a positive control.

March 0.5.0 accepts the positive accessor-to-`power10` fixture but reports
`refinement_unverified`: its solver does not propagate the opaque accessor call
into that proof. The accessor declares the 0..255 refinement and constructors
enforce it at runtime; rejection of negative precision literals is verified.
The contract suite does **not** certify solver proof of accessor propagation.

No RPC, private keys, signing, address checksums, live ingestion, NFT model,
bridges, UTXO selection, chain finality, valuation, tax policy, durable storage,
or JSON/CSV codecs. This package is not an authorization or compliance system.
