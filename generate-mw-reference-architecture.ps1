#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$SampleMode,
    [ValidateSet('healthy', 'degraded')]
    [string]$SampleDataset = 'healthy',
    [string]$TenantId,
    [ValidateSet('dark', 'light')]
    [string]$Theme = 'dark',
    [switch]$IncludePII,
    [string]$WorkspaceId
)

$script:RootPath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:TemplatePath = Join-Path $script:RootPath 'mw-reference-architecture.html'
$script:HealthyPath = Join-Path $script:RootPath 'sample-data\healthy.json'
$script:DegradedPath = Join-Path $script:RootPath 'sample-data\degraded.json'
$script:Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if (-not $OutputPath) {
    $OutputPath = $script:RootPath
}

if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Required JSON file not found: $Path"
    }

    return (Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 30)
}

function Find-Component {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Contract,
        [Parameter(Mandatory = $true)]
        [string]$ComponentId
    )

    foreach ($layer in $Contract.layers) {
        foreach ($component in $layer.components) {
            if ($component.id -eq $ComponentId) {
                return $component
            }
        }
    }

    return $null
}

function Get-StatusForScore {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Score
    )

    if ($Score -lt 0.55) {
        return 'fail'
    }
    if ($Score -lt 0.75) {
        return 'warn'
    }
    return 'pass'
}

function Set-ComponentTelemetry {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Contract,
        [Parameter(Mandatory = $true)]
        [string]$ComponentId,
        [Parameter(Mandatory = $true)]
        [double]$Adoption,
        [Parameter(Mandatory = $true)]
        [string]$SignalSummary,
        [string]$Status
    )

    $component = Find-Component -Contract $Contract -ComponentId $ComponentId
    if (-not $component) {
        return
    }

    $safeScore = [Math]::Round([Math]::Max(0.0, [Math]::Min(1.0, $Adoption)), 2)
    $component.telemetry.adoption = $safeScore
    $component.telemetry.status = if ($Status) { $Status } else { Get-StatusForScore -Score $safeScore }
    $component.telemetry.signalSummary = $SignalSummary
    $component.telemetry.lastChecked = (Get-Date).ToString('o')
}

function Get-GraphCollectionCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    try {
        $response = Invoke-MgGraphRequest -Method GET -Uri $Uri -ErrorAction Stop
        if ($null -ne $response.value) {
            return @($response.value).Count
        }
        return 0
    }
    catch {
        return $null
    }
}

function Get-LiveContract {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        [string]$WorkspaceId,
        [switch]$IncludePII
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    $contract = Read-JsonFile -Path $script:HealthyPath
    $contract.mode = 'live'
    $contract.generated = (Get-Date).ToString('o')
    $contract.assumptions = @(
        'Live contract is built from read-only Graph queries and optional KQL enrichment.',
        'If a signal cannot be collected, the baseline healthy sample value is retained and noted.',
        'Tenant display name is sanitized unless -IncludePII is explicitly supplied.'
    )

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        $warnings.Add('Microsoft Graph PowerShell SDK is not installed; live mode fell back to the healthy sample.') | Out-Null
        return [pscustomobject]@{
            Contract = $contract
            Warnings = $warnings
            UsedFallback = $true
        }
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue | Out-Null

    $scopes = @(
        'Directory.Read.All',
        'Policy.Read.All',
        'DeviceManagementManagedDevices.Read.All',
        'CloudPC.Read.All'
    )

    try {
        $context = Get-MgContext
        if (-not $context) {
            Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome | Out-Null
        }
        elseif ($TenantId -and $context.TenantId -ne $TenantId) {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome | Out-Null
        }
    }
    catch {
        $warnings.Add("Could not establish Microsoft Graph context. Healthy sample retained. $($_.Exception.Message)") | Out-Null
        return [pscustomobject]@{
            Contract = $contract
            Warnings = $warnings
            UsedFallback = $true
        }
    }

    try {
        $organization = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=displayName' -ErrorAction Stop
        $displayName = if ($IncludePII -and $organization.value[0].displayName) {
            $organization.value[0].displayName
        }
        else {
            'Tenant Snapshot'
        }
        $contract.tenant.displayName = $displayName

        $policyCount = Get-GraphCollectionCount -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?$top=999&$select=id'
        $managedResponse = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?$top=999&$select=id,complianceState' -ErrorAction Stop
        $managedDevices = @($managedResponse.value)
        $managedCount = $managedDevices.Count
        $compliantCount = @($managedDevices | Where-Object { $_.complianceState -eq 'compliant' }).Count
        $autopilotCount = Get-GraphCollectionCount -Uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?$top=999&$select=id'
        $cloudPcCount = Get-GraphCollectionCount -Uri 'https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/cloudPCs?$top=999&$select=id'

        $complianceRatio = if ($managedCount -gt 0) { [double]$compliantCount / [double]$managedCount } else { 0.45 }
        $policyScore = if ($null -ne $policyCount) { [Math]::Min([double]$policyCount / 5.0, 0.98) } else { 0.65 }
        $autopilotScore = if ($managedCount -gt 0 -and $null -ne $autopilotCount) { [Math]::Min([double]$autopilotCount / [double]$managedCount * 2.0, 0.95) } else { 0.5 }
        $cloudPcScore = if ($null -ne $cloudPcCount) { [Math]::Min([double]$cloudPcCount / 250.0, 0.92) } else { 0.55 }
        $avdScore = if ($managedCount -gt 0) { [Math]::Max(0.55, [Math]::Min($complianceRatio + 0.08, 0.9)) } else { 0.62 }
        $purviewScore = if ($managedCount -gt 0) { [Math]::Max(0.4, [Math]::Min($complianceRatio - 0.08, 0.82)) } else { 0.56 }
        $gsaScore = if ($null -ne $policyCount) { [Math]::Max(0.3, [Math]::Min([double]$policyCount / 8.0, 0.8)) } else { 0.42 }

        $policyCountValue = if ($null -ne $policyCount) { $policyCount } else { 0 }
        $cloudPcCountValue = if ($null -ne $cloudPcCount) { $cloudPcCount } else { 0 }

        Set-ComponentTelemetry -Contract $contract -ComponentId 'conditional-access' -Adoption $policyScore -SignalSummary ("{0} Conditional Access policies discovered via Graph." -f $policyCountValue)
        Set-ComponentTelemetry -Contract $contract -ComponentId 'intune' -Adoption $complianceRatio -SignalSummary ("{0}/{1} managed devices currently report compliant." -f $compliantCount, $managedCount)
        Set-ComponentTelemetry -Contract $contract -ComponentId 'autopatch' -Adoption ([Math]::Max(0.35, [Math]::Min($complianceRatio - 0.1, 0.92))) -SignalSummary 'Autopatch score is inferred from current compliance and managed device posture.'
        Set-ComponentTelemetry -Contract $contract -ComponentId 'windows-365' -Adoption $cloudPcScore -SignalSummary ("{0} Cloud PCs discovered via Microsoft Graph." -f $cloudPcCountValue)
        Set-ComponentTelemetry -Contract $contract -ComponentId 'avd' -Adoption $avdScore -SignalSummary 'AVD score inferred from managed endpoint posture and optional KQL enrichment.'
        Set-ComponentTelemetry -Contract $contract -ComponentId 'purview' -Adoption $purviewScore -SignalSummary 'Purview score retained as a safe heuristic unless additional compliance data is injected.'
        Set-ComponentTelemetry -Contract $contract -ComponentId 'global-secure-access' -Adoption $gsaScore -SignalSummary 'Global Secure Access score inferred from Conditional Access policy maturity.'
        Set-ComponentTelemetry -Contract $contract -ComponentId 'log-analytics' -Adoption ([Math]::Max(0.55, [Math]::Min($complianceRatio + 0.05, 0.94))) -SignalSummary 'Operations score derived from current managed device posture.'
    }
    catch {
        $warnings.Add("Graph data collection was only partially successful. Some sample defaults were retained. $($_.Exception.Message)") | Out-Null
    }

    if ($WorkspaceId -and (Get-Command Invoke-AzOperationalInsightsQuery -ErrorAction SilentlyContinue)) {
        try {
            $query = @'
Heartbeat
| summarize LastSeen=max(TimeGenerated) by Computer
| summarize ActiveHosts=count()
'@
            $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $query -Timespan (New-TimeSpan -Days 7) -ErrorAction Stop
            $activeHosts = 0
            if ($result.Results -and $result.Results.Count -gt 0) {
                $activeHosts = [int]$result.Results[0].ActiveHosts
            }
            if ($activeHosts -gt 0) {
                $score = [Math]::Max(0.55, [Math]::Min([double]$activeHosts / 100.0, 0.95))
                Set-ComponentTelemetry -Contract $contract -ComponentId 'avd' -Adoption $score -SignalSummary ("{0} active AVD-related hosts surfaced via Log Analytics in the last 7 days." -f $activeHosts)
            }
        }
        catch {
            $warnings.Add("Workspace enrichment failed; base live contract was still produced. $($_.Exception.Message)") | Out-Null
        }
    }

    return [pscustomobject]@{
        Contract = $contract
        Warnings = $warnings
        UsedFallback = $false
    }
}

if (-not (Test-Path $script:TemplatePath)) {
    throw "Template HTML not found: $script:TemplatePath"
}

$useSample = $SampleMode -or [string]::IsNullOrWhiteSpace($TenantId)
$warnings = New-Object System.Collections.Generic.List[string]

if ($useSample) {
    $jsonPath = if ($SampleDataset -eq 'degraded') { $script:DegradedPath } else { $script:HealthyPath }
    $contract = Read-JsonFile -Path $jsonPath
    $contract.generated = (Get-Date).ToString('o')
    $mode = 'sample'
    $label = if ($SampleDataset -eq 'degraded') { 'Degraded sample' } else { 'Healthy sample' }
}
else {
    $live = Get-LiveContract -TenantId $TenantId -WorkspaceId $WorkspaceId -IncludePII:$IncludePII
    $contract = $live.Contract
    foreach ($warning in $live.Warnings) {
        $warnings.Add($warning) | Out-Null
    }
    $mode = if ($live.UsedFallback) { 'sample' } else { 'live' }
    $label = if ($live.UsedFallback) { 'Healthy sample fallback' } else { 'Live Graph snapshot' }
}

$contractJson = $contract | ConvertTo-Json -Depth 30 -Compress
$overrideScript = "<script>window.__MW_INITIAL_DATA__ = $contractJson; window.__MW_INITIAL_MODE__ = '$mode'; window.__MW_INITIAL_LABEL__ = '$label'; window.__MW_INITIAL_THEME__ = '$Theme';</script>"

$templateHtml = Get-Content -Path $script:TemplatePath -Raw -Encoding UTF8
$finalHtml = $templateHtml.Replace('</body>', "$overrideScript`r`n</body>")

$htmlOut = Join-Path $OutputPath ("mw-reference-architecture-{0}.html" -f $script:Timestamp)
$jsonOut = Join-Path $OutputPath ("mw-reference-architecture-{0}.json" -f $script:Timestamp)

$finalHtml | Out-File -FilePath $htmlOut -Encoding UTF8 -Force
$contractJson | Out-File -FilePath $jsonOut -Encoding UTF8 -Force

Write-Host ''
Write-Host 'Modern Workplace Reference Architecture Explorer' -ForegroundColor Cyan
Write-Host ('  HTML: {0}' -f $htmlOut) -ForegroundColor Green
Write-Host ('  JSON: {0}' -f $jsonOut) -ForegroundColor Green
Write-Host ('  Mode: {0}' -f $mode) -ForegroundColor Yellow
Write-Host ('  Theme: {0}' -f $Theme) -ForegroundColor Yellow

if ($warnings.Count -gt 0) {
    Write-Host ''
    Write-Host 'Warnings:' -ForegroundColor DarkYellow
    foreach ($warning in $warnings) {
        Write-Host ('  - {0}' -f $warning) -ForegroundColor DarkYellow
    }
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Cyan