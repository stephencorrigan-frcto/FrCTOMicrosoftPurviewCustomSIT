<#
.SYNOPSIS
  Creates DLP policies that use the code SITs from this repo. Preview by default; -Apply creates them.

.DESCRIPTION
  Creates NEW policies only. An existing policy with the same name is skipped, unless this script created it and it
  is missing rules (for example after a failed run): then only the missing rules are added. Nothing is edited or removed:

    <Prefix> - External Email        Exchange, all mailboxes
        rule "Code Sent to External Recipients"   code SIT match + recipient outside the organisation -> alert, audit only
    <Prefix> - Endpoint              Endpoint DLP, all devices
        rule "Code Pasted or Uploaded to Websites" PasteToBrowser + CloudEgress = Audit -> alert
        rule "Code Copied Off Device"              CopyPaste + NetworkShare + RemovableMedia = Audit, log only (no alert)
    <Prefix> - External Attachments  (optional, -IncludeAttachmentAudit) every external email with an attachment, log only

  Policies are created in simulation mode (TestWithoutNotifications) unless you choose -Mode. Nothing is blocked:
  every action is audit. Users are never notified.

  The code SITs must already be imported (scripts\Import-CustomSITs.ps1). Names are read from definitions\code-sits.json.

  Website scope: PasteToBrowser / CloudEgress apply to all sites unless you scope them in the portal to a sensitive
  service domain group (for example the Microsoft-managed "Generative AI Websites" group). See docs\POLICIES.md.

.PARAMETER AlertRecipients
  Email addresses that receive alerts for the alerting rules.

.PARAMETER Confidence
  High (default) or Medium for the code SITs in the alerting rules. The copy-off-device rule always uses High.

.PARAMETER AdminUpn
  Optional. Pre-fills the Microsoft sign-in window; leave it out to be asked for the account.

.PARAMETER SkipConnect
  Use the Security & Compliance session that is already open (Connect-IPPSSession) and leave it open.
  Used by Start-Deployer.ps1 and Invoke-CodeSitDeployment.ps1.

.PARAMETER Force
  With -Apply, do not ask for YES (the caller has already confirmed).

.EXAMPLE
  .\New-CodeDlpPolicies.ps1 -AdminUpn admin@contoso.com -AlertRecipients secops@contoso.com
  .\New-CodeDlpPolicies.ps1 -AdminUpn admin@contoso.com -AlertRecipients secops@contoso.com -IncludeAttachmentAudit -Apply
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
    [switch]$Apply,
    [switch]$Force,
    [switch]$SkipConnect,
    [string]$Definitions = (Join-Path $PSScriptRoot '..\definitions\code-sits.json')
)
$ErrorActionPreference = 'Stop'
$defs = Get-Content $Definitions -Raw | ConvertFrom-Json
$wanted = @($defs.sits | Where-Object { $_.maturity -eq 'stable' -or ($IncludeExperimental -and $_.maturity -eq 'experimental') } | ForEach-Object { $_.name })
$minConf = if ($Confidence -eq 'High') { '85' } else { '75' }

# Content condition. Microsoft's trainable classifier is only accepted inside the "groups" form of the condition.
function Get-SitCondition([string]$min, [bool]$classifier) {
    $types = @(foreach ($n in $wanted) { @{ name = $n; mincount = '1'; minconfidence = $min; maxconfidence = '100' } })
    if (-not $classifier) { return , $types }
    $types += @{ name = 'Source code'; classifiertype = 'MLModel' }   # Microsoft trainable classifier
    return @{ operator = 'And'; groups = @(@{ operator = 'Or'; name = 'Default'; sensitivetypes = $types }) }
}
$toolComment = 'Created by New-CodeDlpPolicies.ps1 (custom code SITs).'

# Rules: MinConfidence = the code SIT confidence for the content condition ($null = no content condition)
$plan = @(
    [ordered]@{ Policy = "$Prefix - External Email"; Location = 'Exchange'; Rules = @(
        [ordered]@{ Name = 'Code Sent to External Recipients'; MinConfidence = $minConf; Params = @{ AccessScope = 'NotInOrganization'; GenerateAlert = $AlertRecipients; ReportSeverityLevel = 'High' } }) }
    [ordered]@{ Policy = "$Prefix - Endpoint"; Location = 'Endpoint'; Rules = @(
        [ordered]@{ Name = 'Code Pasted or Uploaded to Websites'; MinConfidence = $minConf; Params = @{ GenerateAlert = $AlertRecipients; ReportSeverityLevel = 'High'
                    EndpointDlpRestrictions = @(@{ Setting = 'PasteToBrowser'; Value = 'Audit' }, @{ Setting = 'CloudEgress'; Value = 'Audit' }) } }
        [ordered]@{ Name = 'Code Copied Off Device'; MinConfidence = '85'; Params = @{ ReportSeverityLevel = 'Low'
                    EndpointDlpRestrictions = @(@{ Setting = 'CopyPaste'; Value = 'Audit' }, @{ Setting = 'NetworkShare'; Value = 'Audit' }, @{ Setting = 'RemovableMedia'; Value = 'Audit' }) } }) }
)
if ($IncludeAttachmentAudit) {
    $plan += [ordered]@{ Policy = "$Prefix - External Attachments"; Location = 'Exchange'; Rules = @(
        [ordered]@{ Name = 'External Email With Attachment'; MinConfidence = $null; Params = @{ AccessScope = 'NotInOrganization'; DocumentSizeOver = '1B'; ReportSeverityLevel = 'Low' } }) }
}

function New-PlannedRule($p, $r) {
    $prm = $r.Params.Clone()
    if ($r.MinConfidence) { $prm.ContentContainsSensitiveInformation = Get-SitCondition $r.MinConfidence $IncludeSourceCodeClassifier.IsPresent }
    try { New-DlpComplianceRule -Name $r.Name -Policy $p.Policy @prm -ErrorAction Stop | Out-Null; "  created rule: $($r.Name)"; return }
    catch {
        if (-not ($IncludeSourceCodeClassifier -and $r.MinConfidence) -or $_.Exception.Message -match 'GenerateAlert') { throw }
        Write-Warning "  rule '$($r.Name)' was refused with Microsoft's classifier ($($_.Exception.Message.Split("`n")[0].Trim('|'))). Retrying without it; add it in the portal."
    }
    $prm.ContentContainsSensitiveInformation = Get-SitCondition $r.MinConfidence $false
    New-DlpComplianceRule -Name $r.Name -Policy $p.Policy @prm -ErrorAction Stop | Out-Null; "  created rule (without classifier): $($r.Name)"
}

if (-not $SkipConnect) {
    Import-Module ExchangeOnlineManagement
    $conn = @{ ShowBanner = $false }; if ($AdminUpn) { $conn.UserPrincipalName = $AdminUpn }
    Connect-IPPSSession @conn   # Microsoft sign-in window: username, password, MFA
}
try {
    # prerequisites: SITs present
    $missing = @($wanted | Where-Object { -not (Get-DlpSensitiveInformationType -Identity $_ -ErrorAction SilentlyContinue) })
    if ($missing) {
        if ($Apply) { "These SITs are not in the tenant: $($missing -join ', '). Import them first (scripts\Import-CustomSITs.ps1). Nothing changed."; return }
        Write-Warning "Not in the tenant yet: $($missing -join ', '). They must be imported before the policies can be created."
    }

    # alert recipients must resolve in this tenant; check when the session can look them up
    if (Get-Command Get-Recipient -ErrorAction SilentlyContinue) {
        $unknown = @($AlertRecipients | Where-Object { $_ -ne 'SiteAdmin' -and -not (Get-Recipient -Identity $_ -ErrorAction SilentlyContinue) })
        if ($unknown) { Write-Warning "Alert recipients not found in this tenant: $($unknown -join ', '). Purview only accepts mailboxes, mail users or contacts in the tenant (or SiteAdmin); the alerting rules will fail." }
    }

    "== Plan (mode: $Mode, code SIT confidence: $Confidence, alerts to: $($AlertRecipients -join ', '))"
    "SITs used: $($wanted -join ', ')" + $(if ($IncludeSourceCodeClassifier) { ', Source code (Microsoft classifier)' } else { '' })
    foreach ($p in $plan) {
        $existing = Get-DlpCompliancePolicy -Identity $p.Policy -ErrorAction SilentlyContinue
        $p.Exists = [bool]$existing
        $p.Todo = @($p.Rules)
        $note = ''
        if ($existing) {
            if ([string]$existing.Comment -ne $toolComment) { $p.Todo = @(); $note = '  -> ALREADY EXISTS (not created by this tool), skipped' }
            else {
                $have = @(Get-DlpComplianceRule -Policy $p.Policy -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
                $p.Todo = @($p.Rules | Where-Object { $have -notcontains $_.Name })
                $note = if ($p.Todo) { "  -> EXISTS, $($p.Todo.Count) missing rule(s) will be added" } else { '  -> ALREADY EXISTS and complete, skipped' }
            }
        }
        "`nPolicy: $($p.Policy)  [$($p.Location)]$note"
        foreach ($r in $p.Rules) {
            $acts = if ($r.Params.EndpointDlpRestrictions) { ($r.Params.EndpointDlpRestrictions | ForEach-Object { "$($_.Setting)=$($_.Value)" }) -join ', ' } else { 'audit' }
            $mark = if ($p.Todo -contains $r) { '' } else { '  (exists)' }
            "  rule: $($r.Name)$mark  | actions: $acts | alert: $(if ($r.Params.GenerateAlert) { 'yes' } else { 'no (log only)' })"
        }
    }
    if (-not $Apply) { "`nPREVIEW ONLY. Nothing changed. Re-run with -Apply to create these policies."; return }
    if (-not $Force -and (Read-Host "`nType YES to create the policies above") -cne 'YES') { "Cancelled. Nothing changed."; return }

    $failures = @()
    foreach ($p in ($plan | Where-Object { $_.Todo })) {
        try {
            if (-not $p.Exists) {
                $locParams = if ($p.Location -eq 'Exchange') { @{ ExchangeLocation = 'All' } } else { @{ EndpointDlpLocation = 'All' } }
                New-DlpCompliancePolicy -Name $p.Policy -Mode $Mode @locParams -Comment $toolComment | Out-Null
                "Created policy: $($p.Policy)"
            } else { "Completing policy: $($p.Policy)" }
        } catch { $failures += "policy '$($p.Policy)': $($_.Exception.Message.Trim('|'))"; "FAILED: policy '$($p.Policy)'"; continue }
        foreach ($r in $p.Todo) {
            try { New-PlannedRule $p $r }
            catch {
                $msg = $_.Exception.Message.Split("`n")[0].Trim('|')
                if ($msg -match 'GenerateAlert') { $msg = "an alert recipient is not a mailbox, mail user or contact in this tenant ($($AlertRecipients -join ', ')). Use an address in the customer's tenant, or SiteAdmin, and run again: missing rules are added to the policy." }
                $failures += "rule '$($r.Name)': $msg"; "  FAILED: rule '$($r.Name)'"
            }
        }
    }
    if ($failures) {
        "`nNot created:"; $failures | ForEach-Object { "  - $_" }
        throw "$($failures.Count) policy item(s) were not created. Fix the cause above and run again; existing items are kept and only the missing ones are added."
    }
    if ($Mode -like 'Test*') {
        "`nDone. Policies are in simulation ($Mode). Review matches in Activity explorer, then switch each on:"
        "  Set-DlpCompliancePolicy -Identity '<policy name>' -Mode Enable"
    } else { "`nDone. Policies are in mode '$Mode'." }
}
finally { if (-not $SkipConnect) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } }
