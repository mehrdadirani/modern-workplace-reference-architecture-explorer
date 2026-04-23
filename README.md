# Modern Workplace Reference Architecture Explorer

Interactive, portable reference architecture dashboard for Modern Workplace and EUC scenarios.

This project packages a self-contained HTML explorer, sample datasets, and a PowerShell generator that can emit timestamped HTML and JSON outputs from either public-safe fixtures or live Microsoft Graph data.

## Why this exists

Modern Workplace conversations often split across too many artifacts: executive slides, platform diagrams, operational dashboards, and migration notes. This repo combines those perspectives into one reusable asset that works for:

- architecture walkthroughs
- operations and service health reviews
- legacy-to-modern transition mapping
- Zero Trust coverage conversations
- portfolio demos and public showcases

## What is included

- `index.html`: GitHub Pages entrypoint for the live hosted demo.
- `mw-reference-architecture.html`: the main self-contained explorer template.
- `generate-mw-reference-architecture.ps1`: PowerShell 5.1+ generator for sample or live output.
- `sample-data/healthy.json`: public-safe healthy sample contract.
- `sample-data/degraded.json`: public-safe degraded sample contract.
- `examples/healthy-sample.html`: generated HTML example from the healthy sample.
- `examples/healthy-sample.json`: generated JSON example from the healthy sample.
- `examples/degraded-sample.html`: generated HTML example from the degraded sample.
- `examples/degraded-sample.json`: generated JSON example from the degraded sample.
- `docs/run-samples.md`: quick instructions for sample-driven usage.
- `docs/run-live.md`: live-mode prerequisites and execution steps.

## Quick start

### Option 1: open the dashboard directly

Open `index.html` or `mw-reference-architecture.html` in Edge or Chrome.

The dashboard already contains embedded healthy and degraded demo data, so it works from `file://` with no server and no build step.

### Option 2: generate your own sample output

Run from PowerShell 5.1 or newer:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
cd .\modern-workplace-reference-architecture-explorer-public

.\generate-mw-reference-architecture.ps1 -SampleMode -SampleDataset healthy
.\generate-mw-reference-architecture.ps1 -SampleMode -SampleDataset degraded -Theme light
```

Each run emits:

- a timestamped HTML report
- a timestamped JSON sidecar

### Option 3: run against your own environment

Live mode requires:

- PowerShell 5.1+
- Microsoft Graph PowerShell SDK
- permission to consent to read-only Graph scopes
- optionally, Azure PowerShell support for Log Analytics enrichment

Example:

```powershell
.\generate-mw-reference-architecture.ps1 -TenantId "00000000-0000-0000-0000-000000000000"
```

For the full live setup, see [docs/run-live.md](docs/run-live.md).

## How the dashboard works

The explorer presents:

- a layered architecture view across identity, device, workload, data, network, and operations
- component-level telemetry summaries with dependency mapping
- a legacy-to-modern transition matrix
- a Zero Trust coverage view
- a geography tab with a fallback visualization that still works offline
- a methodology tab that exposes the JSON contract and explains the live-data model

## Public-safety and sanitization

The included fixtures are sanitized and suitable for public sharing:

- tenant names use generic placeholders such as `Contoso`
- no tenant IDs, UPNs, secrets, or real device names are embedded
- live mode keeps the tenant label generic unless `-IncludePII` is explicitly supplied

If you publish your own generated outputs, review them before sharing.

## Sample workflows

If you just want to demonstrate the project safely:

1. Open `index.html`.
2. Switch between the healthy and degraded sample from the header.
3. Load the JSON files from `sample-data/` to validate import behavior.
4. Open the HTML files in `examples/` if you want pre-generated report examples.

For command examples, see [docs/run-samples.md](docs/run-samples.md).

## Live environment workflow

If you want to adapt this to your own tenant:

1. Install the Microsoft Graph PowerShell SDK.
2. Confirm you can sign in and consent to the required read-only scopes.
3. Run the generator with `-TenantId`.
4. Optionally add `-WorkspaceId` to enrich AVD or operations signals from Log Analytics.
5. Review the produced JSON before sharing it publicly.

Detailed prerequisites and scope explanations live in [docs/run-live.md](docs/run-live.md).

## GitHub Pages

This repo is structured so `index.html` can be served directly from GitHub Pages. Once Pages is enabled for the repository root, the hosted demo will open without a build pipeline.

## Data contract summary

Required top-level fields:

- `version`
- `generated`
- `tenant.displayName`
- `tenant.regions[]`
- `layers[]`
- `edges[]`
- `legacyMap[]`

Each component includes telemetry fields such as:

- `telemetry.status`
- `telemetry.adoption`
- `telemetry.signalSummary`
- `telemetry.lastChecked`

The full schema is visible inside the dashboard under the `Methodology` tab.

## Repository contents for readers

If you arrive here from LinkedIn and want to explore quickly, start with:

1. `index.html`
2. `docs/run-samples.md`
3. `docs/run-live.md`

## License

This project is licensed under Apache-2.0. See [LICENSE](LICENSE).