<#
.SYNOPSIS
  Read-only. Exports every non-Microsoft SIT rule package in the tenant to XML, for backup or review.

.EXAMPLE
  .\Export-CustomSITs.ps1 -AdminUpn admin@contoso.com
  .\Export-CustomSITs.ps1 -AdminUpn admin@contoso.com -OutDir C:\Temp\sit-export
#>
param(
    [Parameter(Mandatory)][string]$AdminUpn,
    [string]$OutDir = (Join-Path $PSScriptRoot ('..\exports\sit-export-' + (Get-Date -Format 'yyyyMMdd-HHmm')))
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null
Import-Module ExchangeOnlineManagement
Connect-IPPSSession -UserPrincipalName $AdminUpn -ShowBanner:$false
try {
    $packs = @(Get-DlpSensitiveInformationTypeRulePackage | Where-Object { $_.Publisher -ne 'Microsoft Corporation' })
    "Custom rule packages found: $($packs.Count)"
    $i = 0
    foreach ($p in $packs) {
        $i++
        $xml = [System.Text.Encoding]::Unicode.GetString($p.SerializedClassificationRuleCollection)
        $file = Join-Path $OutDir "rulepack-$i.xml"
        [IO.File]::WriteAllText($file, $xml, [System.Text.Encoding]::Unicode)
        [xml]$d = $xml
        $sits = @($d.RulePackage.Rules.LocalizedStrings.Resource | ForEach-Object { if ($_.Name.'#text') { $_.Name.'#text' } else { [string]$_.Name } })
        "  $file  (id $($d.RulePackage.RulePack.id), version $($p.Version), SITs: $($sits -join ', '))"
    }
}
finally { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue }
"Output: $OutDir   (exports\ is git-ignored: exported packs can contain tenant-specific IDs)"
