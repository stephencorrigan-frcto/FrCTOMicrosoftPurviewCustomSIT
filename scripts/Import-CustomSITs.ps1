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

.EXAMPLE
  .\Import-CustomSITs.ps1 -AdminUpn admin@contoso.com
  .\Import-CustomSITs.ps1 -AdminUpn admin@contoso.com -RulePack ..\sits\code-sits-experimental.xml

.NOTES
  Remove a package:  Remove-DlpSensitiveInformationTypeRulePackage -Identity <rule package id>
  A package cannot be removed while a DLP rule still uses one of its SITs.
#>
param(
    [Parameter(Mandatory)][string]$AdminUpn,
    [string]$RulePack = (Join-Path $PSScriptRoot '..\sits\code-sits-stable.xml')
)
$ErrorActionPreference = 'Stop'
$path = (Resolve-Path $RulePack).Path
[xml]$doc = [IO.File]::ReadAllText($path)
$packId = $doc.RulePackage.RulePack.id
$v = $doc.RulePackage.RulePack.Version; $ver = "$($v.major).$($v.minor).$($v.build).$($v.revision)"
$names = @($doc.RulePackage.Rules.LocalizedStrings.Resource | ForEach-Object { if ($_.Name.'#text') { $_.Name.'#text' } else { [string]$_.Name } })

Import-Module ExchangeOnlineManagement
Connect-IPPSSession -UserPrincipalName $AdminUpn -ShowBanner:$false
try {
    $existing = $null
    try { $existing = Get-DlpSensitiveInformationTypeRulePackage -Identity $packId -ErrorAction Stop } catch { }
    "Rule package : $($doc.RulePackage.RulePack.Details.LocalizedDetails.Name)"
    "Package ID   : $packId"
    "Version      : $ver" + $(if ($existing) { "   (tenant has: $($existing.Version))" } else { '' })
    "Action       : " + $(if ($existing) { 'UPDATE the existing package' } else { 'ADD a new package' })
    "SITs         :"; $names | ForEach-Object { "  - $_" }
    if ((Read-Host "`nType YES to continue") -cne 'YES') { "Cancelled. Nothing changed."; return }

    $bytes = [IO.File]::ReadAllBytes($path)
    if ($existing) { Set-DlpSensitiveInformationTypeRulePackage -FileData $bytes -Confirm:$false }
    else           { New-DlpSensitiveInformationTypeRulePackage -FileData $bytes | Out-Null }

    "`nDone. Custom SITs in the tenant:"
    Get-DlpSensitiveInformationType | Where-Object { $_.Publisher -ne 'Microsoft Corporation' } | Select-Object Name, Publisher, RecommendedConfidence | Format-Table -AutoSize
}
finally { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue }
