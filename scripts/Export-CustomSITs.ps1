<#
.SYNOPSIS
  Read-only. Exports every non-Microsoft SIT rule package in the tenant to XML, for backup or review.

.PARAMETER AdminUpn
  Optional. Pre-fills the Microsoft sign-in window; leave it out to be asked for the account.

.PARAMETER SkipConnect
  Use the Security & Compliance session that is already open (Connect-IPPSSession) and leave it open.
  Used by Start-Deployer.ps1 and Invoke-CodeSitDeployment.ps1.

.EXAMPLE
  .\Export-CustomSITs.ps1 -AdminUpn admin@contoso.com
  .\Export-CustomSITs.ps1 -AdminUpn admin@contoso.com -OutDir C:\Temp\sit-export
#>
param(
    [string]$AdminUpn,
    [string]$OutDir = (Join-Path $PSScriptRoot ('..\exports\sit-export-' + (Get-Date -Format 'yyyyMMdd-HHmm'))),
    [switch]$SkipConnect
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null
if (-not $SkipConnect) {
    Import-Module ExchangeOnlineManagement
    $conn = @{ ShowBanner = $false }; if ($AdminUpn) { $conn.UserPrincipalName = $AdminUpn }
    Connect-IPPSSession @conn   # Microsoft sign-in window: username, password, MFA
}
try {
    $packs = @(Get-DlpSensitiveInformationTypeRulePackage | Where-Object { $_.Publisher -ne 'Microsoft Corporation' })
    "Custom rule packages found: $($packs.Count)"
    $i = 0
    foreach ($p in $packs) {
        $i++
        $xml = [System.Text.Encoding]::Unicode.GetString($p.SerializedClassificationRuleCollection).TrimStart([char]0xFEFF)   # drop a stored byte order mark
        $file = Join-Path $OutDir "rulepack-$i.xml"
        [IO.File]::WriteAllText($file, $xml, [System.Text.Encoding]::Unicode)
        [xml]$d = $xml
        $sits = @($d.RulePackage.Rules.LocalizedStrings.Resource | ForEach-Object { if ($_.Name.'#text') { $_.Name.'#text' } else { [string]$_.Name } })
        "  $file  (id $($d.RulePackage.RulePack.id), version $($p.Version), SITs: $($sits -join ', '))"
    }
}
finally { if (-not $SkipConnect) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } }
"Output: $OutDir   (exports\ is git-ignored: exported packs can contain tenant-specific IDs)"
