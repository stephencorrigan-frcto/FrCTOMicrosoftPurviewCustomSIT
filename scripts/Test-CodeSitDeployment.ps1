<#
.SYNOPSIS
  Read-only. Verifies a deployment: checks the tenant configuration, then compares test emails with the DLP
  rule matches Purview recorded, and gives one verdict.

.DESCRIPTION
  Configuration checks
    - SIT rule packages present at (at least) this repo's version, and every code SIT resolvable
    - each Code DLP policy exists, is enabled, and has finished distributing (Get-DlpCompliancePolicy -DistributionDetail)
    - each expected rule exists, is enabled, and its condition includes every code SIT
    - the AI desktop app group exists with its apps (unless -SkipAppGroup)

  Detection checks (when a test run exists: exports\dlp-test-*\sent.csv from Send-DlpTestEmails.ps1)
    - reads DLP rule matches from Activity explorer (Export-ActivityExplorerData, activity DLPRuleMatch)
    - finds each test email by its subject and compares with its expected result:
        expected match and found              Pass
        expected match, not found yet         Waiting (Fail after -WaitHours)
        expected no match and found           Fail (false positive)
        expected no match, not found          Pass once every expected match of the run has arrived, or after -WaitHours

  Verdict: Verified (configuration and detection pass), ConfigVerified (configuration passes, no test run yet),
  Waiting (distribution or results still pending), NotVerified (any failure). The full result is also left in
  $global:CodeSitVerification and written to verification.json next to the test run.

.EXAMPLE
  .\Test-CodeSitDeployment.ps1 -AdminUpn admin@contoso.com
  .\Test-CodeSitDeployment.ps1 -SkipConnect -IncludeExperimental -SentCsv ..\exports\dlp-test-contoso.com-20261019-111500\sent.csv
#>
param(
    [string]$AdminUpn,
    [string]$Prefix = 'Code DLP',
    [switch]$IncludeExperimental,
    [switch]$IncludeAttachmentAudit,
    [switch]$SkipAppGroup,
    [string]$AppGroupName = 'AI desktop apps',
    [string[]]$AppExecutables = @('claude.exe'),
    [string]$SentCsv,
    [double]$WaitHours = 2,
    [switch]$SkipConnect,
    [string]$Definitions = (Join-Path $PSScriptRoot '..\definitions\code-sits.json')
)
$ErrorActionPreference = 'Stop'
$defs = Get-Content $Definitions -Raw | ConvertFrom-Json
$sitNameById = @{}; foreach ($x in $defs.sits) { $sitNameById[[string]$x.id] = $x.name }
if (-not $SentCsv) {
    $latest = Get-ChildItem (Join-Path $PSScriptRoot '..\exports') -Filter sent.csv -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { $SentCsv = $latest.FullName }
}

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Area, [string]$Name, [ValidateSet('Pass', 'Fail', 'Wait', 'Info')][string]$Status, [string]$Detail) {
    $checks.Add([pscustomobject]@{ Area = $Area; Name = $Name; Status = $Status; Detail = $Detail })
}

$policies = @(
    @{ Name = "$Prefix - External Email"; Rules = @('Code Sent to External Recipients'); Required = $true }
    @{ Name = "$Prefix - Endpoint"; Rules = @('Code Pasted or Uploaded to Websites', 'Code Copied Off Device'); Required = $true }
    @{ Name = "$Prefix - External Attachments"; Rules = @('External Email With Attachment'); Required = [bool]$IncludeAttachmentAudit; NoSits = $true }
)
$allRuleNames = @($policies | ForEach-Object { $_.Rules })

if (-not $SkipConnect) {
    Import-Module ExchangeOnlineManagement
    $conn = @{ ShowBanner = $false }; if ($AdminUpn) { $conn.UserPrincipalName = $AdminUpn }
    Connect-IPPSSession @conn
}
try {
    $emailRuleText = ''
    # experimental pack: checked when asked for, or when the tenant already has it
    $expPack = $null; try { $expPack = Get-DlpSensitiveInformationTypeRulePackage -Identity $defs.packs.experimental.id -ErrorAction Stop } catch { }
    if ($expPack -and -not $IncludeExperimental) { $IncludeExperimental = [switch]$true }
    $maturities = @('stable') + $(if ($IncludeExperimental) { 'experimental' } else { @() })
    $wanted = @($defs.sits | Where-Object { $maturities -contains $_.maturity } | ForEach-Object { $_.name })

    # ---------- configuration ----------
    foreach ($m in $maturities) {
        $pack = $defs.packs.$m
        $have = $null; try { $have = Get-DlpSensitiveInformationTypeRulePackage -Identity $pack.id -ErrorAction Stop } catch { }
        if (-not $have) { Add-Check 'SITs' "$($pack.name)" 'Fail' 'rule package not in the tenant' }
        else {
            $ok = $true; try { $ok = [version]$have.Version -ge [version]$pack.version } catch { }
            Add-Check 'SITs' "$($pack.name)" $(if ($ok) { 'Pass' } else { 'Fail' }) "version $($have.Version)$(if (-not $ok) { ", expected $($pack.version)" })"
        }
    }
    $missing = @($wanted | Where-Object { -not (Get-DlpSensitiveInformationType -Identity $_ -ErrorAction SilentlyContinue) })
    Add-Check 'SITs' "$($wanted.Count) code SITs" $(if ($missing) { 'Fail' } else { 'Pass' }) $(if ($missing) { "missing: $($missing -join ', ')" } else { 'all present' })

    foreach ($p in $policies) {
        $pol = Get-DlpCompliancePolicy -Identity $p.Name -DistributionDetail -ErrorAction SilentlyContinue
        if (-not $pol) {
            if ($p.Required) { Add-Check 'Policies' $p.Name 'Fail' 'policy not found' }
            continue
        }
        $mode = [string]$pol.Mode
        $modeText = switch ($mode) { 'Enable' { 'on' } 'TestWithoutNotifications' { 'simulation' } 'TestWithNotifications' { 'simulation with notifications' } default { $mode } }
        if (-not $pol.Enabled -or $mode -eq 'Disable') { Add-Check 'Policies' $p.Name 'Fail' "policy is off (mode $mode)" }
        else {
            $dist = [string]$pol.DistributionStatus
            $status = switch ($dist) { 'Success' { 'Pass' } 'Pending' { 'Wait' } default { 'Fail' } }
            $detail = "mode: $modeText, distribution: $dist"
            if ($status -eq 'Fail' -and $pol.DistributionResults) { $detail += ' (' + ((@($pol.DistributionResults) | ForEach-Object { [string]$_ }) -join '; ') + ')' }
            if ($status -eq 'Wait') { $detail += ' (usually up to an hour after a change)' }
            Add-Check 'Policies' $p.Name $status $detail
        }
        $rules = @(Get-DlpComplianceRule -Policy $p.Name -ErrorAction SilentlyContinue)
        foreach ($rn in $p.Rules) {
            $r = $rules | Where-Object { $_.Name -eq $rn } | Select-Object -First 1
            if (-not $r) { Add-Check 'Rules' $rn 'Fail' "missing from $($p.Name)"; continue }
            if ($r.Disabled) { Add-Check 'Rules' $rn 'Fail' 'rule is disabled'; continue }
            if ($p.NoSits) { Add-Check 'Rules' $rn 'Pass' 'enabled'; continue }
            $text = [string]$r.AdvancedRule + ' ' + (($r.ContentContainsSensitiveInformation | ConvertTo-Json -Depth 8 -Compress) -as [string])
            if ($rn -eq 'Code Sent to External Recipients') { $emailRuleText = $text }
            $absent = @($wanted | Where-Object { $text -notmatch [regex]::Escape($_) })
            $alert = if ($r.GenerateAlert) { "; alerts to $(@($r.GenerateAlert) -join ', ')" } else { '' }
            Add-Check 'Rules' $rn $(if ($absent) { 'Fail' } else { 'Pass' }) $(if ($absent) { "condition is missing: $($absent -join ', ')" } else { "enabled, all $($wanted.Count) code SITs$alert" })
        }
    }

    if (-not $SkipAppGroup) {
        $cfg = Get-PolicyConfig
        $raw = $cfg.DlpAppGroups
        $groups = @(if ($raw -is [string]) { $raw | ConvertFrom-Json } else { $raw })
        $g = $groups | Where-Object { $_.Name -eq $AppGroupName } | Select-Object -First 1
        if (-not $g) { Add-Check 'Endpoint' "App group '$AppGroupName'" 'Fail' 'not found' }
        else {
            $apps = @(@($g.Apps) | ForEach-Object { if ($_ -is [string]) { $_ | ConvertFrom-Json } else { $_ } } | ForEach-Object { $_ } | ForEach-Object { [string]$_.ExecutableName } | Where-Object { $_ })
            $lack = @($AppExecutables | Where-Object { $apps -notcontains $_ })
            Add-Check 'Endpoint' "App group '$AppGroupName'" $(if ($lack) { 'Fail' } else { 'Pass' }) $(if ($lack) { "missing: $($lack -join ', ')" } else { "apps: $($apps -join ', ')" })
        }
    }

    # ---------- detection ----------
    $emails = @(); $ruleCounts = [ordered]@{}; $runInfo = $null
    $sent = @()
    if ($SentCsv -and (Test-Path $SentCsv)) { $sent = @(Import-Csv $SentCsv | Where-Object { $_.Status -eq 'Sent' }) }
    $firstSent = if ($sent) { ($sent | ForEach-Object { [datetime]$_.Time } | Sort-Object | Select-Object -First 1) } else { $null }
    $since = if ($firstSent) { $firstSent.AddMinutes(-10) } else { (Get-Date).AddHours(-24) }
    if ($since -lt (Get-Date).AddDays(-29)) { $since = (Get-Date).AddDays(-29) }   # Activity explorer keeps 30 days

    $records = @()
    try {
        $cookie = $null; $pages = 0
        do {
            $q = @{ StartTime = $since; EndTime = (Get-Date); OutputFormat = 'Json'; PageSize = 5000; Filter1 = @('Activity', 'DLPRuleMatch'); ErrorAction = 'Stop' }
            if ($cookie) { $q.PageCookie = $cookie }
            $res = Export-ActivityExplorerData @q
            $data = $res.ResultData
            if ($data) { $records += @((&{ if ($data -is [string]) { $data | ConvertFrom-Json } else { $data } }) | ForEach-Object { $_ }) }   # 5.1 returns a JSON array as one object
            $cookie = $res.WaterMark; $pages++
        } while (-not $res.LastPage -and $cookie -and $pages -lt 10)
        Add-Check 'Detection' 'Activity explorer' 'Info' "$($records.Count) DLP rule match(es) since $($since.ToString('yyyy-MM-dd HH:mm'))"
    } catch {
        $m = $_.Exception.Message.Split("`n")[0].Trim('|')
        if ($m -match 'denied|permission|authori|forbidden') { $m += ' (needs an Activity explorer role, for example Compliance Administrator)' }
        Add-Check 'Detection' 'Activity explorer' 'Fail' "could not read Activity explorer: $m"
    }

    $recText = @($records | ForEach-Object { $_ | ConvertTo-Json -Depth 10 -Compress })
    foreach ($rn in $allRuleNames) { $ruleCounts[$rn] = @($recText | Where-Object { $_ -match [regex]::Escape($rn) }).Count }

    $planFile = Join-Path $PSScriptRoot '..\tests\manual\TEST-PLAN.md'
    $plan = @{}
    if (Test-Path $planFile) {
        $lines = @(Get-Content $planFile | Where-Object { $_ -like '|*' })
        if ($lines.Count -ge 3) {
            $hdr = @($lines[0].Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
            foreach ($l in $lines | Select-Object -Skip 2) {
                $c = @($l.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
                $row = @{}; for ($k = 1; $k -lt $c.Count -and $k -lt $hdr.Count; $k++) { if ($c[$k] -match '^\d+$') { $row[$hdr[$k]] = [int]$c[$k] } }
                $plan[$c[0]] = $row
            }
        }
    }
    $ruleSits = @($defs.sits | Where-Object { $emailRuleText -and $emailRuleText -match [regex]::Escape($_.name) } | ForEach-Object { $_.name })
    $ruleLevel = 85
    if ($emailRuleText -match '"confidencelevel"\s*:\s*"(High|Medium|Low)"') { $ruleLevel = @{ High = 85; Medium = 75; Low = 65 }[$Matches[1]] }
    elseif ($emailRuleText -match '"minconfidence"\s*:\s*"?(\d+)') { $ruleLevel = [int]$Matches[1] }
    function Get-ExpectedMatch([string]$file) {
        if (-not $ruleSits -or -not $plan.ContainsKey($file)) { return @{ Match = $null; Text = '' } }
        $hits = @($ruleSits | Where-Object { $plan[$file][$_] -ge $ruleLevel } | ForEach-Object { ($_ -replace '^Source Code - ', '') -replace ' Source Code$', '' })
        if ($hits) { @{ Match = $true; Text = 'expect match: ' + ($hits -join ', ') } } else { @{ Match = $false; Text = 'expect no match' } }
    }
    if ($ruleSits) { Add-Check 'Detection' 'Expected results' 'Info' "from the deployed rule: $($ruleSits.Count) SITs at confidence $ruleLevel or above, and tests\manual\TEST-PLAN.md" }

    if ($sent) {
        $runInfo = [pscustomobject]@{ RunId = $sent[0].RunId; Sent = $firstSent; Count = $sent.Count; Csv = $SentCsv; Sender = $sent[0].Sender; Recipients = $sent[0].Recipients }
        $age = ((Get-Date) - $firstSent).TotalHours
        foreach ($row in $sent) {
            $hitIdx = @(for ($k = 0; $k -lt $records.Count; $k++) {
                $rec = $records[$k]
                if ([string]$rec.EmailInfo.Subject -eq $row.Subject -or [string]$rec.ItemName -eq $row.Subject -or $recText[$k].Contains($row.Subject)) { $k }
            })
            $rulesHit = @($hitIdx | ForEach-Object { $rr = [string]$records[$_].PolicyMatchInfo.RuleName; if ($rr) { $rr } else { $t = $recText[$_]; $allRuleNames | Where-Object { $t -match [regex]::Escape($_) } } } | Select-Object -Unique)
            $sitsHit = @($hitIdx | ForEach-Object { @($records[$_].SensitiveInfoTypeData) } | Where-Object { $_ } | ForEach-Object {
                $n = $sitNameById[[string]$_.SensitiveInfoTypeId]; if ($n) { (($n -replace '^Source Code - ', '') -replace ' Source Code$', '') + " $($_.Confidence)" } } | Select-Object -Unique)
            $exp = Get-ExpectedMatch $row.File
            $expText = if ($null -eq $exp.Match) { $row.Expected } else { $exp.Text }
            $emails += [pscustomobject]@{ File = $row.File; Format = $row.Format; Subject = $row.Subject; Expected = $exp.Match; ExpectedText = $expText
                                          Observed = ($hitIdx.Count -gt 0); Rules = ($rulesHit -join ', '); Sits = ($sitsHit -join ', '); Status = '' }
        }
        $positivesArrived = -not @($emails | Where-Object { $_.Expected -eq $true -and -not $_.Observed })
        foreach ($e in $emails) {
            $e.Status = if ($null -eq $e.Expected) { 'Info' }
                elseif ($e.Expected -and $e.Observed) { 'Pass' }
                elseif ($e.Expected) { if ($age -ge $WaitHours) { 'Fail' } else { 'Wait' } }
                elseif ($e.Observed) { 'Fail' }
                elseif ($positivesArrived -or $age -ge $WaitHours) { 'Pass' } else { 'Wait' }
        }
    }

    # ---------- verdict ----------
    $cfgChecks = @($checks | Where-Object { $_.Area -ne 'Detection' })
    $all = @($cfgChecks) + @($checks | Where-Object { $_.Area -eq 'Detection' }) + @($emails)
    $verdict = if (@($all | Where-Object Status -eq 'Fail').Count) { 'NotVerified' }
        elseif (@($all | Where-Object Status -eq 'Wait').Count) { 'Waiting' }
        elseif (-not $emails) { 'ConfigVerified' }
        else { 'Verified' }
    $pass = @($emails | Where-Object Status -eq 'Pass').Count
    $summary = switch ($verdict) {
        'Verified'       { "Configuration is correct and all $($emails.Count) test emails behaved as expected." }
        'ConfigVerified' { 'Configuration is correct. Send test emails to verify detection.' }
        'Waiting'        { $w = @($all | Where-Object Status -eq 'Wait'); "Waiting on $($w.Count) item(s): " + ((@($w | Select-Object -First 3 | ForEach-Object { if ($_.File) { "$($_.File) ($($_.Format))" } else { $_.Name } }) -join ', ')) + $(if ($emails) { ". $pass of $($emails.Count) test emails confirmed so far." } else { '.' }) }
        'NotVerified'    { $f = @($all | Where-Object Status -eq 'Fail'); "$($f.Count) problem(s): " + ((@($f | Select-Object -First 3 | ForEach-Object { if ($_.File) { "$($_.File) ($($_.Format)) " + $(if ($_.Expected) { "was not detected after $WaitHours hours" } else { 'was detected but should not be' }) } else { "$($_.Name): $($_.Detail)" } }) -join '; ')) }
    }
    $result = [pscustomobject]@{ Verdict = $verdict; Summary = $summary; Checked = (Get-Date); Checks = $checks.ToArray(); Emails = @($emails); Run = $runInfo; RuleMatches = $ruleCounts; WaitHours = $WaitHours }
    $global:CodeSitVerification = $result
    if ($SentCsv -and (Test-Path $SentCsv)) { try { $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path (Split-Path $SentCsv) 'verification.json') -Encoding UTF8 } catch { } }

    # ---------- report ----------
    $mark = @{ Pass = 'PASS'; Fail = 'FAIL'; Wait = 'WAIT'; Info = 'INFO' }
    "== Configuration"
    foreach ($c in $checks) { "  [{0}] {1}: {2}" -f $mark[$c.Status], $c.Name, $c.Detail }
    if ($runInfo) {
        "`n== Test run $($runInfo.RunId): $($runInfo.Count) email(s) sent $($runInfo.Sent.ToString('yyyy-MM-dd HH:mm')) from $($runInfo.Sender)"
        foreach ($e in $emails) {
            $obs = if ($e.Observed) { "matched ($($e.Rules))" + $(if ($e.Sits) { " by $($e.Sits)" } else { '' }) } else { 'no match recorded' }
            "  [{0}] {1} ({2}): {3}; {4}" -f $mark[$e.Status], $e.File, $e.Format, $e.ExpectedText, $obs
        }
    } else { "`n== No test run found. Send test emails from the Test email tab (or Send-DlpTestEmails.ps1)." }
    "`n== Rule matches since $($since.ToString('yyyy-MM-dd HH:mm'))"
    foreach ($k in $ruleCounts.Keys) { "  $k : $($ruleCounts[$k])" }
    "`nVERDICT: $($verdict.ToUpper()). $summary"
}
finally { if (-not $SkipConnect) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } }
