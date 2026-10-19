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
$maturities = @('stable') + $(if ($IncludeExperimental) { 'experimental' } else { @() })
$wanted = @($defs.sits | Where-Object { $maturities -contains $_.maturity } | ForEach-Object { $_.name })
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

    $records = @()
    try {
        $cookie = $null; $pages = 0
        do {
            $q = @{ StartTime = $since; EndTime = (Get-Date).AddMinutes(5); OutputFormat = 'Json'; PageSize = 5000; Filter1 = @('Activity', 'DLPRuleMatch'); ErrorAction = 'Stop' }
            if ($cookie) { $q.PageCookie = $cookie }
            $res = Export-ActivityExplorerData @q
            $data = $res.ResultData
            if ($data) { $records += @((&{ if ($data -is [string]) { $data | ConvertFrom-Json } else { $data } }) | ForEach-Object { $_ }) }   # 5.1 returns a JSON array as one object
            $cookie = $res.WaterMark; $pages++
        } while (-not $res.LastPage -and $cookie -and $pages -lt 10)
        Add-Check 'Detection' 'Activity explorer' 'Info' "$($records.Count) DLP rule match(es) since $($since.ToString('yyyy-MM-dd HH:mm'))"
    } catch { Add-Check 'Detection' 'Activity explorer' 'Fail' "could not read Activity explorer: $($_.Exception.Message.Split("`n")[0]) (needs an Activity explorer role, for example Compliance Administrator)" }

    $recText = @($records | ForEach-Object { $_ | ConvertTo-Json -Depth 10 -Compress })
    foreach ($rn in $allRuleNames) { $ruleCounts[$rn] = @($recText | Where-Object { $_ -match [regex]::Escape($rn) }).Count }

    if ($sent) {
        $runInfo = [pscustomobject]@{ RunId = $sent[0].RunId; Sent = $firstSent; Count = $sent.Count; Csv = $SentCsv; Sender = $sent[0].Sender; Recipients = $sent[0].Recipients }
        $age = ((Get-Date) - $firstSent).TotalHours
        foreach ($row in $sent) {
            $hitIdx = @(for ($k = 0; $k -lt $recText.Count; $k++) { if ($recText[$k].Contains($row.Subject)) { $k } })
            $rulesHit = @($allRuleNames | Where-Object { $rn = $_; @($hitIdx | Where-Object { $recText[$_] -match [regex]::Escape($rn) }).Count })
            $exp = if ($row.Expected -like 'expect match*') { $true } elseif ($row.Expected -like 'expect no match*') { $false } else { $null }
            $emails += [pscustomobject]@{ File = $row.File; Format = $row.Format; Subject = $row.Subject; Expected = $exp; ExpectedText = $row.Expected
                                          Observed = ($hitIdx.Count -gt 0); Rules = ($rulesHit -join ', '); Status = '' }
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
            $obs = if ($e.Observed) { "matched ($($e.Rules))" } else { 'no match recorded' }
            "  [{0}] {1} ({2}): {3}; {4}" -f $mark[$e.Status], $e.File, $e.Format, $e.ExpectedText, $obs
        }
    } else { "`n== No test run found. Send test emails from the Test email tab (or Send-DlpTestEmails.ps1)." }
    "`n== Rule matches since $($since.ToString('yyyy-MM-dd HH:mm'))"
    foreach ($k in $ruleCounts.Keys) { "  $k : $($ruleCounts[$k])" }
    "`nVERDICT: $($verdict.ToUpper()). $summary"
}
finally { if (-not $SkipConnect) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } }
