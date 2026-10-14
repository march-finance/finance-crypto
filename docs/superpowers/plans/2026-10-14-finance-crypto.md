# finance-crypto Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved chain-neutral crypto accounting library, producing balanced ledger drafts from normalized events.

**Architecture:** Opaque network/asset descriptors and event references feed exact amount and fee constructors. Event builders produce immutable envelopes and balanced drafts; finance-ledger owns validation, posting, replay checks, and reversals. No chain SDK or serialization dependency.

**Tech Stack:** March 0.5.0, Forge, sibling finance-core and finance-ledger path dependencies, Check/Gen property tests.

**Spec:** `docs/superpowers/specs/2026-10-14-finance-crypto-design.md`

## Global Constraints

- Project location: `/Users/80197052/code/finance-crypto`.
- Compiler: March 0.5.0, pinned in `.march-version`.
- Each library remains usable without the next. finance-crypto depends on finance-ledger and finance-core, not finance-codec.
- No mutable registry, actor service, network capability, or ambient clock is required.
- All quantities are existing FinanceAmount.Quantity values with strictly positive atoms; zero/negative amounts are rejected.
- The destination journal remains authoritative for account existence, asset declarations, replay conflicts, and atomic append.
- Fees are additional gross debits from funding. Builders never subtract them from the principal implicitly.
- Retries must reuse source, reference, timestamps, and postings.
- Keep the envelope alongside the returned posted entry in caller-owned storage.

## Review Focus

1. Opaque identities must not collide when identifiers contain colons or Unicode; Task 1 pins literal encodings and separator permutations.
2. One transaction may produce multiple events; Task 1 pins distinct reference keys and Task 3 posts both into one journal.
3. Fiat or wrong-network amounts must not slip into on-chain events; Tasks 2 and 3 reject undescribed and mismatched principal/fee assets.
4. Fee funding may alias principal custody intentionally, but must not silently net out principal movement; Task 3 pins withdrawal 10 + fee 1 = debit 11 and rejects inconsistent account definitions.
5. Caller-supplied account values may disagree with the destination journal; Task 3 proves ledger rejection and absence of partial postings.

## Execution and repository setup

Recommended execution: native implementation in this chat, followed by one fresh-context review. Tasks share a small ordered interface chain, so implementing them serially avoids coordination overhead.

Use the requested directory directly as the new repository. It currently contains only the approved design and this plan; preserve both. Initialize a repository on `codex/finance-crypto-v0.1` rather than nesting this package in the March compiler checkout. No remote creation, push, or publication is part of this plan. Commit the reviewed design/plan first, then each independently verified task.

## File map

- `forge.toml`, `.march-version`, `.gitignore`: package/dependency/toolchain setup.
- `lib/error.march`: CryptoError and wrapped dependency errors.
- `lib/identity.march`: network, descriptor, exact amount and identity helpers.
- `lib/reference.march`: opaque origin and deterministic metadata.
- `lib/fee.march`: account compatibility, fee/gas invariants, balanced fee legs.
- `lib/event.march`: opaque context, envelope, transfer/deposit/withdrawal/trade/fee-only builders.
- `test/support_test.march`: reusable fixture constructors and Result expectation.
- `test/identity_test.march`, `test/reference_test.march`, `test/fee_test.march`, `test/event_test.march`, `test/properties_test.march`: real behavior tests.
- `fixtures/contracts/*.march`, `scripts/check-contracts.sh`: compile-time boundary checks.
- `README.md`, `CHANGELOG.md`: usable examples, semantics, limitations and verification.

## Shared interface decisions

These concrete choices implement the spec's semantic requirements without adding chain-specific policy:

- `CryptoIdentity.Amount` is an opaque pair of `FinanceAmount.Quantity` and `Option(CryptoIdentity.Asset)`. `amount(descriptor, quantity)` checks exact asset identity and precision and requires positive atoms. `exchange_amount(quantity)` requires positive atoms and retains no chain descriptor. This makes on-chain provenance checkable without parsing core asset strings. Neither constructor copies numeric representations.
- A reference's network accessor returns `Option(Network)`: Some for on-chain, None for exchange. On-chain events require every principal and fee Amount to carry a matching descriptor; exchange events accept either form.
- `CryptoFee.Kind = ServiceFee | Gas`. Gas always requires a native descriptor; its network is checked against the event reference. Exchange references reject Gas. A token fee can be ServiceFee but not Gas.
- `CryptoEvent.Context` bundles explicit entry ID, Reference, and derived FinanceMetadata. Context construction checks the entry ID using LedgerAccount.valid_id and uses CryptoReference.metadata. No independent mutable timestamps.
- `CryptoEvent.Kind = Transfer | Deposit | Withdrawal | Trade | FeeOnly`. FeeOnly means exactly fee postings; it does not infer whether a transaction succeeded.
- Account equality for reused IDs includes classification, asset identity and precision. Builders reject conflicting same-ID definitions anywhere in their principal/fee inputs. They may reuse a consistently defined custody account as fee funding.

### Task 1: Identity and deterministic event references

**Files:** package configuration; `lib/error.march`, `lib/identity.march`, `lib/reference.march`; identity/reference/support tests.

**Interfaces produced:**

```text
CryptoError.Error = InvalidId | InvalidAmount | AssetMismatch | NetworkMismatch |
  InvalidAccountRole | AccountAlias | InvalidGasAsset | ConflictingAccount |
  Core(FinanceError.Error) | Ledger(LedgerError.Error)

CryptoIdentity.Network                         opaque
CryptoIdentity.Asset                           opaque
CryptoIdentity.AssetKind = Native | Token
CryptoIdentity.Amount                          opaque
network(namespace:String, reference:String) -> Result(Network, Error)
namespace(Network) -> String
network_reference(Network) -> String
network_id(Network) -> String
same_network(Network, Network) -> Bool
native(Network, precision:Int) -> Result(Asset, Error)
token(Network, contract:String, precision:Int) -> Result(Asset, Error)
asset_network(Asset) -> Network
asset_kind(Asset) -> AssetKind
contract(Asset) -> Option(String)
core_asset(Asset) -> FinanceAsset.Asset
precision(Asset) -> {Int | _ >= 0 && _ <= 255}
amount(Asset, FinanceAmount.Quantity) -> Result(Amount, Error)
exchange_amount(FinanceAmount.Quantity) -> Result(Amount, Error)
quantity(Amount) -> FinanceAmount.Quantity
descriptor(Amount) -> Option(Asset)
component(String) -> String
valid_id(String) -> Bool

CryptoReference.Reference                       opaque
on_chain(Network, transactionId:String, eventId:String) -> Result(Reference, Error)
exchange(venue:String, accountScope:String, eventId:String) -> Result(Reference, Error)
network(Reference) -> Option(Network)
key(Reference) -> String
metadata(Reference, source:String, effective:Int, recorded:Int)
  -> Result(FinanceMetadata.Metadata, Error)
```

- [ ] Create Forge manifest and version pin with apply_patch. Use local paths `../finance-core` and `../finance-ledger`; ignore `.march/` and `.forge/`. Do not run the hyphen-name Forge scaffold that previously generated invalid March module names.

```toml
[package]
name = "finance-crypto"
version = "0.1.0"
type = "lib"
description = "Exact chain-neutral crypto event accounting for March"
[deps]
finance-core = { path = "../finance-core" }
finance-ledger = { path = "../finance-ledger" }
```

- [ ] Write failing identity/reference tests. Pin network encoding `component(namespace) ++ component(reference)` and reference keys `finance-crypto:v1:chain:` followed by length-prefixed network ID, tx ID and event ID; exchange uses `finance-crypto:v1:exchange:` plus venue, account scope and event ID.

```march
let n = expect(CryptoIdentity.network("test", "1"))
assert (CryptoIdentity.network_id(n) == "4:test1:1")
let r = expect(CryptoReference.on_chain(n, "tx", "0"))
assert (CryptoReference.key(r) == "finance-crypto:v1:chain:9:4:test1:12:tx1:0")
assert (CryptoIdentity.component("é") == "2:é")
```

Add cases for empty/control IDs including DEL (ASCII 127), valid separator-containing IDs, different contract case preserved, namespace/reference separator permutations, network isolation, precisions -1/0/255/256, zero/negative/mismatched Amounts, event IDs in the same transaction, exchange account scopes, and effective > recorded wrapped core error.

- [ ] Run `forge test --seed=42`; confirm missing CryptoIdentity/CryptoReference APIs cause failure before implementation.
- [ ] Implement opaque constructors and accessors. `component` uses `String.byte_size`; `valid_id` rejects empty strings and ASCII <=32 or DEL. Delegate native/token identity and precision checks to FinanceAsset; map errors using Core. Use identical network encoding for equality and core identity generation. Preserve all caller spelling.
- [ ] Run full `forge test --seed=42` and `forge check`; commit Task 1 only after green.

### Task 2: Exact fee and gas specifications

**Files:** `lib/fee.march`, `test/fee_test.march`.

**Consumes:** Task 1 Amount, descriptor, quantity, core_asset, asset_network/kind; existing LedgerAccount and LedgerEntry.

**Interfaces produced:**

```text
CryptoFee.Kind = ServiceFee | Gas
CryptoFee.Fee                                  opaque
make(kind:Kind, amount:Amount, funding:Account, expense:Account) -> Result(Fee, Error)
kind(Fee) -> Kind
amount(Fee) -> Amount
accounts(Fee) -> List(Account)
postings(Fee) -> Result(List(LedgerEntry.Posting), Error)
check_reference(Fee, Reference) -> Result(Unit, Error)
check_amount_reference(Amount, Reference) -> Result(Unit, Error)
check_accounts(List(Account)) -> Result(Unit, Error)
```

- [ ] Write tests requiring fee expense debit and funding credit, rejection of non-Asset funding, non-Expense expense, aliases, wrong account asset/precision, token or undescribed Gas. Require ServiceFee token acceptance and Gas rejection for exchange/wrong-network references.

```march
let fee = expect(CryptoFee.make(CryptoFee.Gas, fee_amount, wallet, gas_expense))
let ps = expect(CryptoFee.postings(fee))
assert (List.length(ps) == 2)
assert (BigInt.is_zero(List.fold_left(ps, BigInt.zero(), fn (n, p) ->
  BigInt.add(n, LedgerEntry.signed_atoms(p)))))
```

Fixture `fee_amount` is 1 native atom, `wallet` AssetAccount and `gas_expense` ExpenseAccount in that asset. Also assert literal account IDs, directions and atom strings so conservation alone cannot certify wrong routing.

- [ ] Run `forge test --seed=42`; confirm missing fee API failure.
- [ ] Implement smart Fee construction, reference checks, and account-definition consistency. Check roles by matching Kind rather than assuming Eq implementation. `check_accounts` checks every reused ID has the same role and exact asset; it permits repeated identical definitions. No posting uses unchecked constructor access.
- [ ] Run full tests and check; commit after green.

### Task 3: Normalized event builders and ledger integration

**Files:** `lib/event.march`, `test/event_test.march`, `test/properties_test.march`.

**Consumes:** Task 1 Reference/Amount/metadata; Task 2 Fee/reference/account consistency checks; LedgerEntry draft/add/posting; LedgerJournal post/validate/post_validated/balance/reverse.

**Interfaces produced:**

```text
CryptoEvent.Context                            opaque
CryptoEvent.Event                              opaque
CryptoEvent.Kind = Transfer | Deposit | Withdrawal | Trade | FeeOnly
context(id:String, ref:Reference, source:String, effective:Int, recorded:Int)
  -> Result(Context, Error)
transfer(Context, Amount, source:Account, destination:Account, Option(Fee)) -> Result(Event, Error)
deposit(Context, Amount, counterparty:Account, custody:Account, Option(Fee)) -> Result(Event, Error)
withdrawal(Context, Amount, custody:Account, counterparty:Account, Option(Fee)) -> Result(Event, Error)
trade(Context, buy:Amount, sell:Amount, receive:Account, pay:Account,
  buyClearing:Account, sellClearing:Account, Option(Fee)) -> Result(Event, Error)
fee_only(Context, Fee) -> Result(Event, Error)
kind(Event) -> Kind
reference(Event) -> Reference
metadata(Event) -> FinanceMetadata.Metadata
draft(Event) -> LedgerEntry.Draft
```

- [ ] Write failing tests before event implementation. Use literal balance fixtures:
  - Transfer 10 atoms: source -10, destination +10; a same-ID source/destination rejects AccountAlias.
  - Deposit 10: custody +10, explicit clearing -10. Withdrawal reverses these directions.
  - Withdrawal 10 plus fee 1 from custody: custody -11, counterparty +10, expense +1.
  - Token transfer plus native gas: token source -10/destination +10, native funding -1/expense +1.
  - Exchange trade buying 2 token atoms for 600 fiat atoms: receive +2, buy clearing -2, pay -600, sell clearing +600. With 1 fiat atom fee, pay -601 and expense +1.
  - Fee-only failed transaction: fee funding -1, expense +1, no token principal movement and exactly two postings.
  - Wrong-network and descriptor-free on-chain principal/fee rejection; exchange fiat acceptance; same-asset trade rejection; wrong custody roles; clearing aliases; inconsistent duplicate account definitions.
  - Retry same event leaves journal count 1; changed amount gives ReplayConflict; another event ID in the same transaction posts independently.
  - Validate returned draft then post_validated; destination chart disagreement fails with ledger error, leaving prior journal balances unchanged.
  - Reverse the posted principal+fee entry with fresh metadata; every balance returns to zero and original journal remains unchanged.

```march
let event = expect(CryptoEvent.withdrawal(ctx, principal, wallet, clearing, Some(fee)))
let (posted, _) = expect(LedgerJournal.post(journal, CryptoEvent.draft(event)))
assert (BigInt.to_string(FinanceAmount.atoms(expect(LedgerJournal.balance(posted, "wallet")))) == "-11")
assert (BigInt.to_string(FinanceAmount.atoms(expect(LedgerJournal.balance(posted, "clearing")))) == "10")
assert (BigInt.to_string(FinanceAmount.atoms(expect(LedgerJournal.balance(posted, "fees")))) == "1")
```

Fixtures explicitly construct wallet/clearing/expense accounts in a zero-decimal test asset, principal 10, fee 1; no expected value comes from event-builder code.

- [ ] Run `forge test --seed=42`, observe missing event APIs.
- [ ] Implement opaque Context and Event. A private finish function checks all account definitions, optional fee reference, appends principal then fee postings in deterministic order, wraps ledger errors, and constructs the immutable envelope. Build principal legs with LedgerEntry.posting. Check Quantity assets against account assets and descriptors before finishing. Kind-specific checks enforce custody roles. Transfer/deposit/withdrawal reject equal endpoint IDs. Trade rejects same buy/sell assets and each custody/clearing alias. Exchange and on-chain reference rules are always checked, even without fees.
- [ ] Add generated tests using `Check.all(Gen.tuple(Gen.int(1,1000000), Gen.int(1,1000)), ...)`: principal n and fee f yield source `-(n+f)`, destination n, expense f; reverse returns all zero. Additional properties vary two trade legs independently and check each asset's account sum, plus replay count. Native, token and exchange-fiat fixtures are separate cases, not one property masking wrong network behavior.
- [ ] Run full tests seed42 and seed123 and `forge check`; commit after green.

### Task 4: Compile-time contracts, documentation, final verification

**Files:** contract fixtures/script; README; CHANGELOG.

**Consumes:** all prior public APIs. No new product API.

- [ ] Create positive fixture exercising Context -> transfer -> draft -> validate -> post_validated in a Result-returning function. Check it compiles before trusting rejection fixtures.
- [ ] Create rejection fixtures for external construction of Network, Asset, Amount, Reference, Fee, Context, Event. Each names its actual hidden constructor and requires unknown_constructor, not arbitrary nonzero exit. An inherited precision-refinement fixture calls `FinanceRounding.power10(-1)` and requires refinement_violated; use `FinanceRounding.power10(CryptoIdentity.precision(asset))` in the positive control to prove the crypto accessor preserves the core refinement.
- [ ] Adapt sibling finance-ledger's contract script: compiler from project version pin or explicit MARCH_COMPILER, MARCH_LIB_PATH includes all three local lib directories, mktemp diagnostics with cleanup trap. Require the positive control and expected error code for every negative fixture. Keep fixtures outside test/ and lib/.
- [ ] Write README with a compiled/tested token-transfer plus native-gas example, exchange trade example, explicit module API table, replay/metadata rules, gross fee semantics, network canonicalization responsibility, custody versus clearing classifications, account-chart authority, and caller persistence obligations. State no finality/signing/valuation guarantees. Add 0.1.0 changelog without claiming publication.
- [ ] Run all commands and inspect exit codes/output:

```sh
forge toolchain which
forge check
forge build --release
forge test --seed=42
forge test --seed=123
forge test --release --seed=20261014
sh scripts/check-contracts.sh
```

Run `forge test --release --seed=20261014` in each sibling project as regression checks. Record counts, failures, compiler identity, and any toolchain warnings.

- [ ] Request one fresh-context whole-library review against the spec, including wrong-network inputs, replay and aliasing. Resolve confirmed blocking findings with failing regression tests first; rerun full verification. Commit final verified files, without creating a remote or publishing.

## Completion criteria

All five modules and documented operations exist; smart constructors reject invalid inputs without panic; per-asset balance and replay behavior are demonstrated by real ledger integration tests; opacity/refinement fixtures pass with positive control; debug/release and sibling regressions pass on March 0.5.0; no blocking review finding remains. Report remaining non-goals explicitly rather than describing the package as a chain SDK.
