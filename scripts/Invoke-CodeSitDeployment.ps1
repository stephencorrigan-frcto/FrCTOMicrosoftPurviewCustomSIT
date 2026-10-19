<#
.SYNOPSIS
  Deploys everything to one tenant in order: SIT backup, SIT import, AI desktop app group, DLP policies.
  Preview by default; -Apply makes the changes. Used by Start-Deployer.ps1; can also be run on its own.

.DESCRIPTION
  One sign-in, then each step runs the existing script for that job with -SkipConnect:

    1. Back up custom SITs      Export-CustomSITs.ps1        (Apply only, read-only)
    2. Import custom SITs       Import-CustomSITs.ps1        stable pack, plus experimental with -IncludeExperimental
    3. AI desktop app group     New-EndpointDlpAppGroup.ps1  (skipped with -SkipAppGroup)
    4. DLP policies             New-CodeDlpPolicies.ps1      simulation mode by default, audit only

  Without -Apply every step previews and nothing changes. With -Apply the whole plan is previewed, you type YES
  once, then the changes are made (or pass -Force when the caller has already confirmed, as the GUI does).
  If a step fails, the remaining steps are skipped. Backups and the run log go to -RunDir.

  Re-running is safe: SITs already at this version are left alone, existing app groups are merged, and
  policies that already exist are skipped.

.EXAMPLE
  .\Invoke-CodeSitDeployment.ps1 -AlertRecipients secops@contoso.com                      # preview, sign-in prompt
  .\Invoke-CodeSitDeployment.ps1 -AlertRecipients secops@contoso.com -IncludeSourceCodeClassifier -Apply
#>
param(
    [string]$AdminUpn,
    [Parameter(Mandatory)][string[]]$AlertRecipients,
    [string]$Prefix = 'Code DLP',
    [ValidateSet('TestWithoutNotifications', 'TestWithNotifications', 'Enable', 'Disable')][string]$Mode = 'TestWithoutNotifications',
    [ValidateSet('High', 'Medium')][string]$Confidence = 'High',
    [switch]$IncludeExperimental,
    [switch]$IncludeSourceCodeClassifier,
    [switch]$IncludeAttachmentAudit,
    [switch]$SkipAppGroup,
    [string]$AppGroupName = 'AI desktop apps',
    [hashtable[]]$Apps = @(@{ Name = 'Claude Desktop'; ExecutableName = 'claude.exe' }),
    [switch]$Apply,
    [switch]$Force,
    [switch]$SkipConnect,
    [string]$RunDir = (Join-Path $PSScriptRoot ('..\exports\deploy-' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$script:failed = $false

function Invoke-Step([string]$Title, [scriptblock]$Body) {
    if ($script:failed) { "`n--- Skipped: $Title (an earlier step failed)"; return }
    "`n=== $Title"
    try {
        & $Body *>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { "ERROR: $_" }
            elseif ($_ -is [System.Management.Automation.WarningRecord]) { "WARNING: $($_.Message)" }
            else { $_ }
        } | Out-String -Stream -Width 200
    }
    catch { "ERROR: $($_.Exception.Message)"; $script:failed = $true }
}

function Invoke-Plan([bool]$Make) {
    $common = @{ SkipConnect = $true }
    $mk = if ($Make) { @{ Apply = $true; Force = $true } } else { @{} }
    if ($Make) {
        Invoke-Step 'Back up existing custom SITs' { & "$here\Export-CustomSITs.ps1" @common -OutDir (Join-Path $RunDir 'sit-backup') }
    }
    $imp = if ($Make) { @{ Force = $true } } else { @{ Preview = $true } }
    Invoke-Step 'Custom SITs: stable pack' { & "$here\Import-CustomSITs.ps1" @common @imp -RulePack "$here\..\sits\code-sits-stable.xml" }
    if ($IncludeExperimental) {
        Invoke-Step 'Custom SITs: experimental pack' { & "$here\Import-CustomSITs.ps1" @common @imp -RulePack "$here\..\sits\code-sits-experimental.xml" }
    }
    if (-not $SkipAppGroup) {
        Invoke-Step "Endpoint DLP app group: $AppGroupName" { & "$here\New-EndpointDlpAppGroup.ps1" @common @mk -GroupName $AppGroupName -Apps $Apps -BackupDir $RunDir }
    }
    $pol = @{ AlertRecipients = $AlertRecipients; Prefix = $Prefix; Mode = $Mode; Confidence = $Confidence
              IncludeExperimental = $IncludeExperimental; IncludeSourceCodeClassifier = $IncludeSourceCodeClassifier; IncludeAttachmentAudit = $IncludeAttachmentAudit }
    Invoke-Step 'DLP policies' { & "$here\New-CodeDlpPolicies.ps1" @common @mk @pol }
}

if (-not $SkipConnect) {
    Import-Module ExchangeOnlineManagement
    $conn = @{ ShowBanner = $false }; if ($AdminUpn) { $conn.UserPrincipalName = $AdminUpn }
    Connect-IPPSSession @conn
}
try {
    if ($Apply) { New-Item -ItemType Directory -Force $RunDir | Out-Null }
    if (-not $Apply -or -not $Force) {
        Invoke-Plan $false
        if (-not $Apply) { "`nPREVIEW ONLY. Nothing changed. Re-run with -Apply to make these changes."; return }
        if ($script:failed) { "`nThe preview failed, so nothing was changed."; return }
        if ((Read-Host "`nType YES to make all the changes above") -cne 'YES') { "Cancelled. Nothing changed."; return }
    }
    Invoke-Plan $true
    "`nRun folder (backups): $((Resolve-Path $RunDir).Path)"
    if ($script:failed) { throw 'One or more steps failed. See the ERROR lines above; later steps were skipped.' }
    "`nDone. Next: the portal steps in docs\SETUP.md (step 8), then the field tests (step 9)."
}
finally { if (-not $SkipConnect) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } }
