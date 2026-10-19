<#
.SYNOPSIS
  Builds a Microsoft Purview custom sensitive information type (SIT) rule package (XML) from definitions\code-sits.json.

.DESCRIPTION
  Each SIT in the JSON has a primary regex, named supporting regexes and confidence patterns
  (for example High 85 = primary + 2 different supporting elements within the proximity window).
  The script checks every regex against the constructs the Purview validator rejects, compiles it,
  and writes a UTF-16 rule package that Import-CustomSITs.ps1 can upload.

.PARAMETER Maturity
  stable (default), experimental, or all. Each maturity is written as its own rule package.

.PARAMETER Version
  Optional rule package version (for example 1.1.0.0). Must be higher than the version already in the tenant when updating.

.EXAMPLE
  .\Build-RulePack.ps1                      # sits\code-sits-stable.xml
  .\Build-RulePack.ps1 -Maturity experimental
#>
param(
    [ValidateSet('stable', 'experimental', 'all')][string]$Maturity = 'stable',
    [string]$Version,
    [string]$Definitions = (Join-Path $PSScriptRoot '..\definitions\code-sits.json'),
    [string]$OutDir = (Join-Path $PSScriptRoot '..\sits')
)
$ErrorActionPreference = 'Stop'
$defs = Get-Content $Definitions -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Force $OutDir | Out-Null

function Test-PurviewRegex([string]$re) {
    # Local approximation of the Purview validator. A clean result is necessary but not sufficient.
    $bad = @()
    if ($re -match '\.[\*\+]|\.\{')             { $bad += 'dot wildcard with a repeat (.* .+ .{n})' }
    if ($re -match '\[\^[^\]]*\][\*\+\{]')       { $bad += 'negated character class with a repeat' }
    if ($re -match '[^\\]\)[\*\+]|[^\\]\)\{\d')  { $bad += 'repeated group' }
    if ($re -match '\{\d+,\d*\}')               { $bad += 'ranged repeat {n,m}' }
    if ($re.Length -gt 1024)                    { $bad += "length $($re.Length) > 1024" }
    try { [void][regex]::new($re) } catch       { $bad += 'does not compile' }
    return $bad
}
function Esc([string]$s) { [System.Security.SecurityElement]::Escape($s) }

$targets = if ($Maturity -eq 'all') { @('stable', 'experimental') } else { @($Maturity) }
foreach ($m in $targets) {
    $pack = $defs.packs.$m
    $sits = @($defs.sits | Where-Object { $_.maturity -eq $m })
    if (-not $sits) { Write-Warning "No SITs with maturity '$m'"; continue }
    $ver = if ($Version) { $Version } else { $pack.version }
    $vp = $ver.Split('.'); while ($vp.Count -lt 4) { $vp += '0' }

    # register regex processors (identical regexes share one processor)
    $proc = [ordered]@{}; $byValue = @{}; $problems = 0
    function Add-Proc([string]$name, [string]$re) {
        if ($byValue.ContainsKey($re)) { return $byValue[$re] }
        $bad = Test-PurviewRegex $re
        if ($bad) { Write-Warning "$name : $($bad -join '; ')"; $script:problems++ }
        $proc[$name] = $re; $byValue[$re] = $name; return $name
    }
    $entityXml = foreach ($s in $sits) {
        $pid_ = Add-Proc "$($s.key)_Primary" $s.primary
        $supIds = foreach ($p in $s.supporting.PSObject.Properties) { Add-Proc "$($s.key)_$($p.Name)" $p.Value }
        $supIds = @($supIds | Select-Object -Unique)
        $pats = foreach ($pt in $s.patterns) {
            $matches_ = ($supIds | ForEach-Object { "<Match idRef=`"$_`" />" }) -join ''
            "<Pattern confidenceLevel=`"$($pt.confidence)`" proximity=`"$($s.proximity)`"><IdMatch idRef=`"$pid_`" /><Any minMatches=`"$($pt.minSupporting)`">$matches_</Any></Pattern>"
        }
        "<Entity id=`"$($s.id)`" patternsProximity=`"$($s.proximity)`" recommendedConfidence=`"$($s.recommendedConfidence)`" relaxProximity=`"false`">$($pats -join '')</Entity>"
    }
    if ($problems) { throw "$problems regex problem(s) found. Fix definitions\code-sits.json before building." }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-16"?>')
    [void]$sb.AppendLine("<RulePackage xmlns=`"http://schemas.microsoft.com/office/2011/mce`"><RulePack id=`"$($pack.id)`"><Version major=`"$($vp[0])`" minor=`"$($vp[1])`" build=`"$($vp[2])`" revision=`"$($vp[3])`" /><Publisher id=`"$($pack.publisherId)`" /><Details defaultLangCode=`"en-us`"><LocalizedDetails langcode=`"en-us`"><PublisherName>$(Esc $pack.publisherName)</PublisherName><Name>$(Esc $pack.name)</Name><Description>$(Esc $pack.name)</Description></LocalizedDetails></Details></RulePack><Rules>")
    foreach ($e in $entityXml) { [void]$sb.AppendLine($e) }
    foreach ($k in $proc.Keys) { [void]$sb.AppendLine("<Regex id=`"$k`">$(Esc $proc[$k])</Regex>") }
    [void]$sb.Append('<LocalizedStrings>')
    foreach ($s in $sits) { [void]$sb.Append("<Resource idRef=`"$($s.id)`"><Name default=`"true`" langcode=`"en-us`">$(Esc $s.name)</Name><Description default=`"true`" langcode=`"en-us`">$(Esc $s.description)</Description></Resource>") }
    [void]$sb.AppendLine('</LocalizedStrings></Rules></RulePackage>')

    $xmlText = $sb.ToString()
    [xml]$check = $xmlText   # throws if not well-formed
    $out = Join-Path $OutDir "code-sits-$m.xml"
    [IO.File]::WriteAllText($out, $xmlText, [System.Text.Encoding]::Unicode)
    "{0}: {1} SITs, {2} regex processors, version {3} -> {4}" -f $m, $sits.Count, $proc.Count, $ver, (Resolve-Path $out)
}
