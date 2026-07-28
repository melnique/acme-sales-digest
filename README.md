# Acme Sports — Sales Digest (Mule 4)

Single Mule 4 application. On a schedule it reads `sales.csv`, enriches each row
with country and FX data, converts amounts to EUR, aggregates a digest and POSTs
it to the Treasury system.

```
scheduler ─▶ read sales.csv ─▶ validate ─▶ enrich (country + FX) ─▶ aggregate ─▶ publish
```

## Deviations from the brief

- **REST Countries `v3.1` is retired** — `restcountries.com/v3.1/alpha` now
  returns a deprecation error. The solution uses **v5**
  (`api.restcountries.com/countries/v5`), which requires a Bearer key, has no
  filter-by-code (free plan caps pages at 100, so the reference is paginated and
  indexed by alpha-2), and returns a different shape (`data.objects[]`,
  `codes.alpha_2`, `names.common`). The index is cached in Object Store (24h TTL).
- **`httpbin.org/post` intermittently returned `503`** — transient, on httpbin's
  side. The POST is built and sent correctly and is retried with backoff. The
  sink host is a property.

## Requirements

- Mule Runtime 4.10.0, Java 17 (not Java 21+): `export JAVA_HOME=$(/usr/libexec/java_home -v 17)`
- Maven 3.9+
- Outbound internet access. REST Countries needs the API key below; Frankfurter
  and httpbin need none.

## Runtime parameters

Both are required on every run (app and tests):

| Property | Purpose |
|----------|---------|
| `mule.env` | Selects the environment file. Use `dev`. |
| `mule.vault.key` | Decrypts the REST Countries key. Real vault key for a live run; any 16-char value for tests (the country call is mocked). |

## Project layout

| Path | Purpose |
|------|---------|
| `src/main/mule/global.xml` | Property loaders, secure-properties, HTTP/File/Object-Store configs |
| `src/main/mule/sales-digest.xml` | Trigger flow, processing flow, country-pagination sub-flow |
| `src/main/resources/modules/Fx.dwl` | Reusable DataWeave (rounding + FX conversion) |
| `src/main/resources/properties/*.yaml` | `common` + per-environment properties |
| `input/sales.csv` | Sample input batch |
| `src/test/munit/` | MUnit suite |

## Properties

`global.xml` loads `common-properties.yaml` and `${mule.env}-properties.yaml`.
Non-secret values are plain; the REST Countries key is encrypted (`![...]`, read
via `secure::countries.apiKey`).

| Property | File | Default | Notes |
|----------|------|---------|-------|
| `scheduler.frequency` | dev | `3600` | Trigger interval in seconds (`3600` = hourly; lower it to test). |
| `file.working.dir` | dev | `input` | Directory the File connector reads from. |
| `treasury.host` | dev | `httpbin.org` | Host the digest is POSTed to. |
| `countries.cache.ttlHours` | common | `24` | Country-cache validity. |
| `http.response.timeout` / `http.retry.count` / `http.retry.delayMs` | common | `10000` / `3` / `2000` | Timeout and retry-with-backoff for external calls. |

## Run (Anypoint Studio)

Import the project, then **Run As → Mule Application**. In **Arguments → VM
arguments**:

```
-Dmule.env=dev -Dmule.vault.key=<vault-key> -Dfile.working.dir=<repo>/input
```

`file.working.dir` is absolute because Studio launches the runtime from its own
directory, not the project root, so the relative default does not resolve.

## Tests

```bash
mvn clean test -Dmule.env=dev -Dmule.vault.key=0123456789abcdef
```

Three MUnit tests, fully offline (Object Store and all HTTP mocked); application
coverage 82.61%.

- `process-sales-batch-happy-path` — validate → enrich → aggregate → publish.
- `process-sales-batch-unknown-country` — unknown country → `region: "UNKNOWN"`; FX skipped for all-EUR.
- `scheduler-flow-reads-file-and-processes` — file read + delegation.
