<#
.SYNOPSIS
  Creates or updates an Endpoint DLP restricted app group (for example "AI desktop apps") without touching other groups.

.DESCRIPTION
  Restricted app groups are referenced by DLP rules ("File activities for apps in restricted app groups") so that
  file access by those apps can be audited or restricted. This script:
    1. reads the tenant's current app groups (Get-PolicyConfig),
    2. saves a backup to exports\ (git-ignored),
    3. adds the group, or merges new apps into it if it already exists (existing apps and other groups are kept),
    4. shows the result and asks you to type YES,
    5. writes the FULL list back with Set-PolicyConfig (the cmdlet replaces the whole collection, which is why
       every existing group is re-sent), then reads it back to confirm.

  Preview only unless -Apply is used. Adding a group changes nothing on devices until a DLP rule references it.

  Executable names must match the process name on the device (Task Manager, Details tab). Check them on a device
  before adding: a wrong name silently matches nothing.

  Format based on Microsoft365DSC's SCPolicyConfig resource; validate in a test tenant first.

.PARAMETER AdminUpn
  Optional. Pre-fills the Microsoft sign-in window; leave it out to be asked for the account.

.PARAMETER SkipConnect
  Use the Security & Compliance session that is already open (Connect-IPPSSession) and leave it open.
  Used by Start-Deployer.ps1 and Invoke-CodeSitDeployment.ps1.

.PARAMETER Force
  With -Apply, do not ask for YES (the caller has already confirmed).

.EXAMPLE
  .\New-EndpointDlpAppGroup.ps1 -AdminUpn admin@contoso.com
  .\New-EndpointDlpAppGroup.ps1 -AdminUpn admin@contoso.com -Apps @{ Name = 'Claude Desktop'; ExecutableName = 'claude.exe' } -Apply

.NOTES
  Restore from a backup:  see the Restore-*.ps1 file written next to the backup.
#>
param(
    [string]$AdminUpn,
    [string]$GroupName = 'AI desktop apps',
    [string]$Description = 'Desktop AI applications. Referenced by DLP rules to log access to sensitive files.',
    [hashtable[]]$Apps = @(@{ Name = 'Claude Desktop'; ExecutableName = 'claude.exe' }),
    [switch]$Apply,
    [switch]$Force,
    [switch]$SkipConnect,
    [string]$BackupDir = (Join-Path $PSScriptRoot '..\exports')
)
$ErrorActionPreference = 'Stop'

function ConvertTo-AppJson($list) { ConvertTo-Json -InputObject @($list) -Depth 5 -Compress }   # -InputObject keeps a one-item list as an array
function Read-Groups($cfg) {
    if (-not $cfg.DlpAppGroups) { return @() }
    $raw = $cfg.DlpAppGroups
    $parsed = if ($raw -is [string]) { $raw | ConvertFrom-Json } else { $raw }
    foreach ($g in @($parsed)) {
        $apps = foreach ($a in @($g.Apps)) { if ($a) { [ordered]@{ Name = [string]$a.Name; ExecutableName = [string]$a.ExecutableName; Quarantine = [bool]::Parse([string]($(if ($null -ne $a.Quarantine) { $a.Quarantine } else { 'False' }))) } } }
        [ordered]@{ Name = [string]$g.Name; Description = [string]$g.Description; Apps = @($apps) }
    }
}

if (-not $SkipConnect) {
    Import-Module ExchangeOnlineManagement
    $conn = @{ ShowBanner = $false }; if ($AdminUpn) { $conn.UserPrincipalName = $AdminUpn }
    Connect-IPPSSession @conn   # Microsoft sign-in window: username, password, MFA
}
try {
    $cfg = Get-PolicyConfig
    $groups = @(Read-Groups $cfg)
    "Current restricted app groups: $($groups.Count)"
    foreach ($g in $groups) { "  - $($g.Name): " + (($g.Apps | ForEach-Object { $_.ExecutableName }) -join ', ') }

    # merge
    $target = $groups | Where-Object { $_.Name -eq $GroupName } | Select-Object -First 1
    $added = @()
    if (-not $target) { $target = [ordered]@{ Name = $GroupName; Description = $Description; Apps = @() }; $groups += $target; $action = 'ADD new group' }
    else { $action = 'UPDATE existing group (existing apps kept)' }
    foreach ($a in $Apps) {
        if (-not $a.ExecutableName) { throw "Each app needs an ExecutableName (for example claude.exe)." }
        if (@($target.Apps | Where-Object { $_.ExecutableName -ieq $a.ExecutableName }).Count -eq 0) {
            $target.Apps = @($target.Apps) + [ordered]@{ Name = $(if ($a.Name) { $a.Name } else { $a.ExecutableName }); ExecutableName = $a.ExecutableName; Quarantine = $false }
            $added += $a.ExecutableName
        }
    }
    "`n== Plan: $action '$GroupName'"
    "  apps after change: " + (($target.Apps | ForEach-Object { "$($_.Name) ($($_.ExecutableName))" }) -join ', ')
    "  newly added: " + $(if ($added) { $added -join ', ' } else { '(none, already present)' })
    "  other groups re-sent unchanged: " + @($groups | Where-Object { $_.Name -ne $GroupName }).Count
    if (-not $added) { "`nNothing to change."; return }
    if (-not $Apply) { "`nPREVIEW ONLY. Nothing changed. Re-run with -Apply."; return }
    if (-not $Force -and (Read-Host "`nType YES to write the restricted app groups") -cne 'YES') { "Cancelled. Nothing changed."; return }

    # backup + restore script
    New-Item -ItemType Directory -Force $BackupDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bk = Join-Path $BackupDir "DlpAppGroups-backup-$stamp.json"
    [IO.File]::WriteAllText($bk, (ConvertTo-Json -InputObject @(Read-Groups $cfg) -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    $restore = @(
        "# Restores restricted app groups from $bk. Run after Connect-IPPSSession."
        "`$g = Get-Content '$bk' -Raw | ConvertFrom-Json"
        "`$p = @(foreach (`$x in @(`$g)) { @{ Name = `$x.Name; Description = `$x.Description; Apps = (ConvertTo-Json -InputObject @(`$x.Apps) -Depth 5 -Compress) } })"
        "Set-PolicyConfig -DlpAppGroups `$p"
    )
    [IO.File]::WriteAllLines((Join-Path $BackupDir "Restore-DlpAppGroups-$stamp.ps1"), $restore)
    "Backup: $bk"

    # write the full collection
    $payload = @(foreach ($g in $groups) { @{ Name = $g.Name; Description = $(if ($g.Description) { $g.Description } else { '' }); Apps = (ConvertTo-AppJson $g.Apps) } })
    Set-PolicyConfig -DlpAppGroups $payload

    # verify
    $after = @(Read-Groups (Get-PolicyConfig))
    $chk = $after | Where-Object { $_.Name -eq $GroupName }
    $lost = @($groups | Where-Object { $n = $_.Name; -not ($after | Where-Object { $_.Name -eq $n }) })
    "`nRead-back: '$GroupName' has " + (($chk.Apps | ForEach-Object { $_.ExecutableName }) -join ', ')
    if ($lost) { Write-Warning "Groups missing after write: $(($lost | ForEach-Object Name) -join ', '). Restore with the Restore script in $BackupDir." }
    else { "All $($after.Count) groups present. Next: reference '$GroupName' in a DLP rule (see docs\SETUP.md, step 8)." }
}
finally { if (-not $SkipConnect) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } }
