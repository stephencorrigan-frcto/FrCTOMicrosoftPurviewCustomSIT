<#
.SYNOPSIS
  Scores custom SIT rule packages (XML) against the sample corpora, offline. Nothing touches a tenant.

.DESCRIPTION
  Models Purview evaluation: a SIT reaches a confidence level when its primary pattern matches and enough
  supporting elements match within the proximity window. Every SIT is scored in case-sensitive and
  case-insensitive mode, because Purview's regex case handling should be confirmed in your tenant
  (see tests\manual\16_case_sensitivity_ALL_CAPS.py).

  Per SIT:   share of its own language samples reaching Medium (75) and High (85)
  Non-code:  any match on business text, data files or markup is a false positive
  Any SIT:   share of all code samples caught by at least one SIT (how DLP rules with "any of these" behave)
  Verdict:   PASS if own-language >= 80% at Medium or above and zero non-code matches in both modes.

  The .NET regex engine is close to, but not identical to, Purview's engine. Confirm in the Purview SIT test tool.

.PARAMETER Set
  all (default), build, holdout, blind1, blind2, blind3 or blind4. See docs\TESTING.md for what each set is.

.PARAMETER WritePlan
  Also writes tests\manual\TEST-PLAN.md with the expected result for each manual test file.

.EXAMPLE
  .\Test-CodeSITs.ps1
  .\Test-CodeSITs.ps1 -Set blind4 -ShowMisses
  .\Test-CodeSITs.ps1 -RulePack ..\sits\code-sits-stable.xml -WritePlan
#>
param(
    [string[]]$RulePack = @((Join-Path $PSScriptRoot '..\sits\code-sits-stable.xml'), (Join-Path $PSScriptRoot '..\sits\code-sits-experimental.xml')),
    [string]$Definitions = (Join-Path $PSScriptRoot '..\definitions\code-sits.json'),
    [ValidateSet('all', 'build', 'holdout', 'blind1', 'blind2', 'blind3', 'blind4')][string]$Set = 'all',
    [switch]$ShowMisses,
    [switch]$WritePlan
)
$ErrorActionPreference = 'Stop'
$samplesRoot = Join-Path $PSScriptRoot 'samples'
$defs = Get-Content $Definitions -Raw | ConvertFrom-Json
$sampleMap = @{}; foreach ($d in $defs.sits) { $sampleMap[$d.id] = @($d.testSamples) }

# ---------- load rule packages ----------
$sits = [ordered]@{}
foreach ($rp in $RulePack) {
    if (-not (Test-Path $rp)) { Write-Warning "Rule package not found: $rp (run scripts\Build-RulePack.ps1)"; continue }
    [xml]$x = [IO.File]::ReadAllText((Resolve-Path $rp))
    $proc = @{}
    foreach ($r in $x.RulePackage.Rules.Regex) { $proc[$r.id] = $r.'#text' }
    foreach ($k in $x.RulePackage.Rules.Keyword) {
        $parts = foreach ($g in @($k.Group)) { foreach ($t in @($g.Term)) { $txt = if ($t.'#text') { $t.'#text' } else { [string]$t }; if ($g.matchStyle -eq 'word') { '\b' + [regex]::Escape($txt) + '(?!\w)' } else { [regex]::Escape($txt) } } }
        $proc[$k.id] = ($parts -join '|')
    }
    $names = @{}; foreach ($res in $x.RulePackage.Rules.LocalizedStrings.Resource) { $names[$res.idRef] = if ($res.Name.'#text') { $res.Name.'#text' } else { [string]$res.Name } }
    foreach ($e in $x.RulePackage.Rules.Entity) {
        $pats = foreach ($p in @($e.Pattern)) {
            @{ level = [int]$p.confidenceLevel; id = $p.IdMatch.idRef
               req = @(@($p.Match) | Where-Object { $_ } | ForEach-Object { $_.idRef })
               any = if ($p.Any) { @(@($p.Any.Match) | ForEach-Object { $_.idRef }) } else { @() }
               min = if ($p.Any) { [int]$p.Any.minMatches } else { 0 }; prox = [int]$e.patternsProximity }
        }
        $sits[$names[$e.id]] = @{ id = $e.id; pats = @($pats | Sort-Object { - $_.level }); proc = $proc; samples = $sampleMap[$e.id] }
    }
}
if (-not $sits.Count) { throw 'No SITs loaded.' }

function Get-Level([string]$text, $sit, $opt) {
    foreach ($p in $sit.pats) {
        foreach ($m in [regex]::Matches($text, $sit.proc[$p.id], $opt)) {
            $lo = [Math]::Max(0, $m.Index - $p.prox); $hi = $m.Index + $m.Length + $p.prox
            $near = { param($procId) foreach ($y in [regex]::Matches($text, $sit.proc[$procId], $opt)) { if ($y.Index -ge $lo -and ($y.Index + $y.Length) -le $hi) { return $true } }; return $false }
            $ok = $true; foreach ($r in $p.req) { if (-not (& $near $r)) { $ok = $false; break } }
            if (-not $ok) { continue }
            $hits = 0; foreach ($a in $p.any) { if (& $near $a) { $hits++ } }
            if ($hits -ge $p.min) { return $p.level }
        }
    }
    return 0
}
function Read-Files([string]$dir) { if (Test-Path $dir) { Get-ChildItem $dir -File -Recurse | Sort-Object FullName | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Lang = $_.Directory.Name; Text = ([IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n") } } } }

$setDirs = if ($Set -eq 'all') { @(Get-ChildItem $samplesRoot -Directory | Sort-Object Name | ForEach-Object Name) } else { @($Set) }
$code = @(foreach ($s in $setDirs) { Read-Files (Join-Path $samplesRoot "$s\code") })
$noncode = @(foreach ($s in $setDirs) { Read-Files (Join-Path $samplesRoot "$s\noncode") })
$modes = [ordered]@{ 'case-sensitive' = [Text.RegularExpressions.RegexOptions]::None; 'case-insensitive' = [Text.RegularExpressions.RegexOptions]::IgnoreCase }
$cs = $modes['case-sensitive']

"Sets: $($setDirs -join ', ') | code samples: $($code.Count) | non-code samples: $($noncode.Count) | SITs: $($sits.Count)`n"
$table = foreach ($name in $sits.Keys) {
    $sit = $sits[$name]
    $own = if ($sit.samples -contains '*') { $code } else { @($code | Where-Object { $sit.samples -contains $_.Lang }) }
    $lv = @($own | ForEach-Object { [pscustomobject]@{ F = "$($_.Lang)/$($_.Name)"; L = (Get-Level $_.Text $sit $cs) } })
    $n = $lv.Count; $o75 = @($lv | Where-Object { $_.L -ge 75 }).Count; $o85 = @($lv | Where-Object { $_.L -ge 85 }).Count
    $fp = @{}; foreach ($mk in $modes.Keys) { $fp[$mk] = @($noncode | Where-Object { Get-Level $_.Text $sit $modes[$mk] } | ForEach-Object Name) }
    if ($ShowMisses) {
        foreach ($missed in ($lv | Where-Object { $_.L -lt 75 })) { Write-Host ("  MISS {0,-38} {1}" -f $name, $missed.F) -ForegroundColor Yellow }
        foreach ($mk in $modes.Keys) { foreach ($fpName in $fp[$mk]) { Write-Host ("  FALSE POSITIVE ({0}) {1,-24} {2}" -f $mk, $name, $fpName) -ForegroundColor Red } }
    }
    $pct = if ($n) { [math]::Round(100 * $o75 / $n) } else { 0 }
    [pscustomobject]@{ SIT = $name; 'Own >=Medium' = "$o75/$n ($pct%)"; 'Own High' = "$o85/$n"
        'Non-code FP (cs)' = $fp['case-sensitive'].Count; 'Non-code FP (ci)' = $fp['case-insensitive'].Count
        Verdict = $(if ($n -and $pct -ge 80 -and $fp['case-sensitive'].Count -eq 0 -and $fp['case-insensitive'].Count -eq 0) { 'PASS' } else { 'REVIEW' }) }
}
$table | Format-Table -AutoSize | Out-String -Width 200

$a75 = 0; $a85 = 0; $miss = @()
foreach ($f in $code) { $best = 0; foreach ($name in $sits.Keys) { $l = Get-Level $f.Text $sits[$name] $cs; if ($l -gt $best) { $best = $l } }
    if ($best -ge 75) { $a75++ } else { $miss += "$($f.Lang)/$($f.Name)" }; if ($best -ge 85) { $a85++ } }
"ANY SIT: $a75/$($code.Count) code samples at Medium or above, $a85/$($code.Count) at High."
if ($ShowMisses -and $miss) { "  not caught by any SIT: $($miss -join ', ')" }

if ($WritePlan) {
    $manual = Join-Path $PSScriptRoot 'manual'
    $names = @($sits.Keys)
    $md = @('# Manual test plan: expected results', '', 'Generated by tests\Test-CodeSITs.ps1 -WritePlan from the rule packages. Confidence each SIT reaches (case-sensitive model): 85 High, 75 Medium, - no match.', '', ('| File | ' + ($names -join ' | ') + ' |'), ('|---|' + (($names | ForEach-Object { '---' }) -join '|') + '|'))
    foreach ($f in (Get-ChildItem $manual -File | Where-Object { $_.Name -notlike 'TEST-PLAN*' } | Sort-Object Name)) {
        $t = [IO.File]::ReadAllText($f.FullName) -replace "`r`n", "`n"
        $cells = foreach ($name in $names) { $l = Get-Level $t $sits[$name] $cs; if ($l) { $l } else { '-' } }
        $md += "| $($f.Name) | $($cells -join ' | ') |"
    }
    $md += @('', 'Files 12 to 15 are for Microsoft credential SITs and negative controls; file 16 checks whether Purview regex matching is case-sensitive (run it in the SIT test tool).')
    [IO.File]::WriteAllLines((Join-Path $manual 'TEST-PLAN.md'), $md)
    "Wrote $(Join-Path $manual 'TEST-PLAN.md')"
}
