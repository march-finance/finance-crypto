# finance-crypto guide

Normalize chain and exchange activity into exact accounting drafts.
March 0.5.0; finance-crypto 0.1.0. This is not a blockchain client or signing SDK.

## Install

Merge into your application's existing `[deps]` section:

```toml
[deps]
finance-core = "0.1.0"
finance-ledger = "0.1.0"
finance-crypto = "0.1.0"
```

Run `forge deps` and commit the application's lockfile. Core and ledger are
explicit here because the example uses their APIs. Pin `.march-version` to
`v0.5.0`; install with `forge toolchain install v0.5.0`.
No wallet, RPC credentials or private key is needed.

## Quickstart: construct a native transfer

Save this complete test as `test/crypto_quickstart_test.march`, then run
`forge test --seed=42`. It builds a one-atom transfer without posting it.
The transaction ID is deliberately illustrative; no chain lookup or address
validation occurs.

```march
mod CryptoQuickstart do
  needs IO.Clock, IO.Process

  fn example() : Result(CryptoEvent.Event, CryptoError.Error) do
    let? network = CryptoIdentity.network("eip155", "1")
    let? native = CryptoIdentity.native(network, 18)
    let asset = CryptoIdentity.core_asset(native)
    let quantity = FinanceAmount.from_atoms(asset, BigInt.one())
    let? amount = CryptoIdentity.amount(native, quantity)
    let? source = Result.map_err(
      LedgerAccount.make("wallet-a", LedgerAccount.AssetAccount, asset),
      fn e -> CryptoError.Ledger(e))
    let? destination = Result.map_err(
      LedgerAccount.make("wallet-b", LedgerAccount.AssetAccount, asset),
      fn e -> CryptoError.Ledger(e))
    let? reference = CryptoReference.on_chain(network, "example-tx", "transfer-0")
    let? context = CryptoEvent.context("transfer-1", reference, "wallet-import", 100, 101)
    CryptoEvent.transfer(context, amount, source, destination, None)
  end

  test "documented native transfer builds two postings" do
    let event = Result.unwrap(example())
    let postings = LedgerEntry.postings(CryptoEvent.draft(event))
    assert (List.length(postings) == 2)
    assert (FinanceAmount.format(LedgerEntry.quantity(List.head(postings))) == "0.000000000000000001")
  end
end
```

The resulting draft debits wallet-b and credits wallet-a by one native atom.
It contains no fee because the final argument is None. Zero is not a valid fee
amount. A successful builder does not mean a chain transaction has occurred or
that the destination journal will accept it.

## Normalize identity before ingestion

`CryptoIdentity.network(namespace, reference)` includes the environment:
mainnet and testnet must have different references. `native(network, precision)`
and `token(network, contractOrMint, precision)` create opaque descriptors.
`core_asset(descriptor)` is the exact asset to put in ledger accounts and
quantities. Do not reconstruct an equivalent-looking asset from a ticker.

Identifiers are case-sensitive, length-prefixed strings. The library rejects
empty components, ASCII whitespace/control characters and DEL, but does not
verify checksums, addresses, contracts or token decimals. Your chain adapter
owns canonicalization, including any protocol-specific case normalization.

`amount(descriptor, quantity)` requires matching asset identity AND precision and
strictly positive atoms. `exchange_amount(quantity)` permits positive fiat or
other core assets without a chain descriptor. Descriptor-free amounts cannot be
used in on-chain events. `quantity` and `descriptor` expose these components.

## References and context

`CryptoReference.on_chain(network, transactionId, eventId)` distinguishes multiple
accounting events in one transaction. Use stable event IDs from your adapter.
`exchange(venue, accountScope, eventId)` separates accounts at one venue.
Reference components are opaque, not validated transaction hashes.

`CryptoEvent.context(id, reference, source, effective, recorded)` creates draft
metadata. Times are caller-supplied UTC Unix seconds, effective <= recorded.
The versioned reference key becomes metadata's external ID; source remains a
separate namespace. Keep all of them stable across retries, including recorded time.

A reference is not proof of confirmation. Your ingestion service decides when
to post and what to do with chain reorganizations.

## Pick an event builder

| Builder | Arguments after context | Principal movements |
| --- | --- | --- |
| transfer | amount, source, destination, optional fee | Credit source; debit destination |
| deposit | amount, counterparty, custody, optional fee | Credit counterparty; debit custody |
| withdrawal | amount, custody, counterparty, optional fee | Credit custody; debit counterparty |
| trade | buy, sell, receive, pay, buyClearing, sellClearing, optional fee | Debit receive/credit buy clearing; credit pay/debit sell clearing |
| fee_only | fee | Debit expense; credit funding |

Transfer endpoints and trade receive/pay accounts must be AssetAccounts.
Deposit/withdrawal custody must be AssetAccount; counterparties and clearing are
explicit, not inferred as income or expense. Buy and sell assets must differ.
Do not alias endpoints or a trade's same-asset custody and clearing account.
Repeated account IDs must have consistent kind, identity and precision.

`CryptoEvent.kind/reference/metadata/draft` inspect the envelope. Builders do not
post: the caller passes the draft to ledger. A ledger retains the draft and
metadata, not the entire crypto envelope; persist any envelope you need separately.

## Fees and gas

`CryptoFee.make(kind, amount, fundingAccount, expenseAccount)` requires
AssetAccount funding and ExpenseAccount expense, both matching the fee asset.
Kinds are Gas and ServiceFee.

Gas must use a native descriptor on the on-chain reference's network.
Token service fees require matching on-chain provenance, not Gas.
Exchange events accept ServiceFee but reject Gas.

All fees are additional gross movements. A principal of 10 and fee of 1 funded
from the same account consume 11, not 10. If an importer supplies a net amount,
normalize it explicitly before calling the builder. A failed transaction with
only paid gas can use fee_only. No sufficient-funds check occurs.

## Errors and boundaries

Crypto operations return `Result(_, CryptoError.Error)`. Wrap a core error with
`Result.map_err(value, fn e -> CryptoError.Core(e))`; wrap ledger errors with
`CryptoError.Ledger(e)` as in the example. Do not unwrap untrusted input.

| Error | Typical cause |
| --- | --- |
| InvalidId | Malformed identity/reference/draft component |
| InvalidAmount | Nonpositive principal or fee |
| AssetMismatch | Descriptor, quantity or account disagree |
| NetworkMismatch | On-chain amount belongs to another network or lacks descriptor |
| InvalidAccountRole | Wrong custody/funding/expense kind |
| AccountAlias | Same ID used for incompatible movement endpoints |
| InvalidGasAsset | Token gas or gas on an exchange reference |
| ConflictingAccount | One ID given inconsistent account definitions |
| Core(error) / Ledger(error) | Validation failed in that dependency |

The library does not sign, broadcast, fetch, price, value, calculate taxes, model
NFT ownership, bridge assets, select UTXOs, establish finality or coordinate writers.
An exact draft is not proof of an external transaction or permission to move funds.

Precision refinements are declared and constructors validate at runtime.
March 0.5.0 reports refinement_unverified for the accessor-to-power10 fixture:
do not claim the solver proves propagation through opaque accessors.
See [verification and detailed semantics](../README.md) and the
[tested quickstart](../test/docs_quickstart_test.march).
