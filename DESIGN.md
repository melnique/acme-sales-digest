# DESIGN — Sales Digest

## Architecture

Single Mule application; no API-led layering, as the scenario is one scheduled
batch job. Three components:

- `sales-digest-scheduler-flow` — trigger and file read only, kept minimal so the
  processing logic is testable without a scheduler or filesystem.
- `process-sales-batch-flow` — validate → enrich (country + FX) → aggregate → publish.
- `country-data-pagination-sub-flow` — country fetch on cache miss, isolated for testing.

Transformations use DataWeave. FX conversion and rounding are shared by the
per-row calculation and the aggregate totals, so they are extracted to a module
(`modules/Fx.dwl`). Row validation is single-use and stays inline.

## Reference data

**Country (REST Countries v5).** The free plan provides no filter-by-code and
caps responses at 100 objects per page. The full reference (~250 countries) is
fetched by pagination (`limit=100` + `offset`), reduced with `response_fields`,
and indexed by alpha-2 code. The index is cached in Object Store with a 24h TTL:
the API is called about once per day rather than per run, and a REST Countries
outage does not fail a run.

**FX (Frankfurter).** One request per run. Distinct non-EUR currencies are
requested in a single `from=EUR&to=…` call and the rates are inverted to
currency→EUR. Frankfurter bases from a single currency, so one call requires
base-EUR plus inversion rather than the per-currency `from={cur}&to=EUR` form.
The call is skipped when the batch is entirely EUR.


## Validation

Rows are validated and normalised (trim, upper-case country/currency) in a single
pass. Structurally invalid rows — missing id or date, malformed code or currency,
non-numeric or non-positive amount — are dropped and counted (`invalid=N`). A
well-formed but unknown country code is retained with `region: "UNKNOWN"`; a
failed reference lookup degrades one row, not the batch.

## Resilience, logging, security

- External calls are wrapped in `until-successful` (retry with backoff); timeout
  and retry counts are properties.
- One correlation id per run, a single-line `rows_read/valid/invalid/countries/
  fx` summary, and error context in the flow's `on-error-continue` handler.
- The REST Countries key is stored encrypted (Secure Properties) and read via
  `secure::`; the vault key is supplied at runtime.

## Scaling

The current design materialises the batch and the derived `enriched` array in
memory and aggregates in a single DataWeave pass — adequate for thousands of
rows, not for ~500k. For that volume the CSV would be streamed in one pass with
per-key totals accumulated via `reduce` instead of `groupBy`; reference data is
already cached and constant. Beyond that, `batch:job` (chunked, disk-backed) is
the appropriate mechanism.