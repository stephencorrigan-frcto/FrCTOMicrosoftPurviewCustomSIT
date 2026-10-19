<#
.SYNOPSIS
  Adds or updates a custom SIT rule package in Microsoft Purview.

.DESCRIPTION
  Reads the rule package ID and version from the XML, checks whether that package already exists in the tenant,
  shows what will happen and asks you to type YES. A new package is added with New-DlpSensitiveInformationTypeRulePackage;
  an existing one is replaced with Set-DlpSensitiveInformationTypeRulePackage (the XML version must be higher than the
  version in the tenant: build with scripts\Build-RulePack.ps1 -Version x.y.z.w).

  Importing SITs does not change any DLP policy. SITs only take effect once a rule uses them.
  Requires the ExchangeOnlineManagement module and a role that can manage DLP (for example Compliance Administrator).

.PARAMETER AdminUpn
  Optional. Pre-fills the Microsoft sign-in window; leave it out to be asked for the account.

.PARAMETER SkipConnect
  Use the Security & Compliance session that is already open (Connect-IPPSSession) and leave it open.
  Used by Start-Deployer.ps1 and Invoke-CodeSitDeployment.ps1.

.PARAMETER Preview
  Show what would happen and stop. Nothing changes.

.PARAMETER Force
  Do not ask for YES (the caller has already confirmed).

.EXAMPLE
  .\Import-CustomSITs.ps1 -AdminUpn admin@contoso.com
  .\Import-CustomSITs.ps1 -AdminUpn admin@contoso.com -RulePack ..\sits\code-sits-experimental.xml

.NOTES
  Remove a package:  Remove-DlpSensitiveInformationTypeRulePackage -Identity <rule package id>
  A package cannot be removed while a DLP rule still uses one of its SITs.
#>
param(
    [string]$AdminUpn,
    [string]$RulePack = (Join-Path $PSScriptRoot '..\sits\code-sits-stable.xml'),
    [switch]$Preview,
    [switch]$Force,
    [switch]$SkipConnect
)
$ErrorActionPreference = 'Stop'
$path = (Resolve-Path $RulePack).Path
[xml]$doc = [IO.File]::ReadAllText($path)
$packId = $doc.RulePackage.RulePack.id
$v = $doc.RulePackage.RulePack.Version; $ver = "$($v.major).$($v.minor).$($v.build).$($v.revision)"
$names = @($doc.RulePackage.Rules.LocalizedStrings.Resource | ForEach-Object { if ($_.Name.'#text') { $_.Name.'#text' } else { [string]$_.Name } })

if (-not $SkipConnect) {
    Import-Module ExchangeOnlineManagement
    $conn = @{ ShowBanner = $false }; if ($AdminUpn) { $conn.UserPrincipalName = $AdminUpn }
    Connect-IPPSSession @conn   # Microsoft sign-in window: username, password, MFA
}
try {
    $existing = $null
    try { $existing = Get-DlpSensitiveInformationTypeRulePackage -Identity $packId -ErrorAction Stop } catch { }
    "Rule package : $($doc.RulePackage.RulePack.Details.LocalizedDetails.Name)"
    "Package ID   : $packId"
    "Version      : $ver" + $(if ($existing) { "   (tenant has: $($existing.Version))" } else { '' })
    $current = $false
    if ($existing) { try { $current = [version]$existing.Version -ge [version]$ver } catch { } }
    "Action       : " + $(if ($current) { 'NONE, the tenant already has this version' } elseif ($existing) { 'UPDATE the existing package' } else { 'ADD a new package' })
    "SITs         :"; $names | ForEach-Object { "  - $_" }
    if ($current) { "`nAlready up to date. Nothing changed."; return }
    if ($Preview) { "`nPREVIEW ONLY. Nothing changed."; return }
    if (-not $Force -and (Read-Host "`nType YES to continue") -cne 'YES') { "Cancelled. Nothing changed."; return }

    $bytes = [IO.File]::ReadAllBytes($path)
    if ($existing) { Set-DlpSensitiveInformationTypeRulePackage -FileData $bytes -Confirm:$false }
    else           { New-DlpSensitiveInformationTypeRulePackage -FileData $bytes | Out-Null }

    "`nDone. Custom SITs in the tenant:"
    Get-DlpSensitiveInformationType | Where-Object { $_.Publisher -ne 'Microsoft Corporation' } | Select-Object Name, Publisher, RecommendedConfidence | Format-Table -AutoSize
}
finally { if (-not $SkipConnect) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } }
