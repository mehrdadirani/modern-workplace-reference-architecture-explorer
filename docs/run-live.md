# Run Live Against Your Own Environment

This guide explains how to generate a live snapshot using Microsoft Graph and optional Log Analytics data.

## What you need

### Required

- Windows PowerShell 5.1 or PowerShell 7+
- the Microsoft Graph PowerShell SDK installed locally
- a tenant ID
- an account that can consent to the required read-only scopes

### Optional

- Azure PowerShell support for `Invoke-AzOperationalInsightsQuery`
- a Log Analytics workspace ID if you want AVD or operations enrichment

## Required Graph scopes

The script uses read-only Microsoft Graph scopes only:

- `Directory.Read.All`
- `Policy.Read.All`
- `DeviceManagementManagedDevices.Read.All`
- `CloudPC.Read.All`

## Install Microsoft Graph PowerShell SDK

Example install command:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

If your environment already uses specific submodules, that is also fine as long as authentication and request commands are available.

## Run live mode

From the repository root:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\generate-mw-reference-architecture.ps1 -TenantId "00000000-0000-0000-0000-000000000000"
```

On first use, the script will attempt to connect to Microsoft Graph and prompt for authentication if needed.

## Add Log Analytics enrichment

If you also want Log Analytics-based enrichment, supply a workspace ID:

```powershell
.\generate-mw-reference-architecture.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -WorkspaceId "11111111-1111-1111-1111-111111111111"
```

This path is optional. If enrichment fails, the base live contract can still be produced.

## Include a real tenant label

By default, live mode keeps the tenant display name sanitized. Only use `-IncludePII` if you intentionally want the real tenant name written into the output:

```powershell
.\generate-mw-reference-architecture.ps1 `
  -TenantId "00000000-0000-0000-0000-000000000000" `
  -IncludePII
```

Do not publish that output publicly unless you have reviewed it.

## Output files

The script writes two timestamped files:

- `mw-reference-architecture-<timestamp>.html`
- `mw-reference-architecture-<timestamp>.json`

The HTML file contains an injected JSON payload so it can be opened directly in a browser.

## Failure behavior

The script is intentionally defensive:

- if Graph SDK is missing, it warns and falls back to the healthy sample
- if Graph authentication fails, it warns and falls back to the healthy sample
- if some live calls fail, it retains sample defaults where needed and still emits output

This makes the tool usable in demos and constrained environments.

## Recommended review before sharing

Before posting your own generated output:

1. Inspect the JSON for tenant identifiers, UPNs, or environment-specific notes.
2. Open the HTML locally and confirm the values shown are safe to share.
3. If you used `-IncludePII`, assume the output is not public-safe until reviewed.