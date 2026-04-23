# Run The Samples

This guide is for readers who want to explore the project without connecting to a live tenant.

## What you need

- Windows PowerShell 5.1 or PowerShell 7+
- a modern browser such as Edge or Chrome

No Microsoft Graph access is required for sample mode.

## Fastest path

Open either of these files directly:

- `index.html`
- `mw-reference-architecture.html`

The page contains embedded healthy and degraded fixtures, so it works immediately from `file://`.

## Use the built-in samples in the UI

1. Open `index.html`.
2. Use the dataset selector in the top header.
3. Switch between `Healthy sample` and `Degraded sample`.
4. Review how the health banner, KPI cards, and component statuses change.

## Load the raw sample JSON files

The repository includes:

- `sample-data/healthy.json`
- `sample-data/degraded.json`

To test JSON import behavior:

1. Open the dashboard.
2. Click `Load JSON`.
3. Select one of the files from `sample-data/`.

The dashboard validates the structure before rendering.

## Generate sample HTML + JSON from PowerShell

Run these commands from the repository root:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\generate-mw-reference-architecture.ps1 -SampleMode -SampleDataset healthy
.\generate-mw-reference-architecture.ps1 -SampleMode -SampleDataset degraded
.\generate-mw-reference-architecture.ps1 -SampleMode -SampleDataset degraded -Theme light
```

Each execution creates:

- `mw-reference-architecture-<timestamp>.html`
- `mw-reference-architecture-<timestamp>.json`

## Use the tracked example outputs

If you want to inspect generated output without running anything, open:

- `examples/healthy-sample.html`
- `examples/degraded-sample.html`

These are generated examples that show what the script emits.

## Troubleshooting

- If PowerShell blocks script execution, run it with `-ExecutionPolicy Bypass` at process scope only.
- If the dashboard opens but looks plain, verify your browser is not blocking local file access.
- If optional online libraries do not load, the dashboard still renders using built-in fallback views.