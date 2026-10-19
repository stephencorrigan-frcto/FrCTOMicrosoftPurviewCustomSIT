<#
.SYNOPSIS
  Creates DLP policies that use the code SITs from this repo. Preview by default; -Apply creates them.

.DESCRIPTION
  Creates NEW policies only (existing policies with the same name are skipped, nothing is edited or removed):

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

function Get-SitList([string]$min) {
    $list = @(foreach ($n in $wanted) { @{ Name = $n; minCount = '1'; minConfidence = $min; maxConfidence = '100' } })
    if ($IncludeSourceCodeClassifier) { $list += @{ Name = 'Source code'; ClassifierType = 'MLModel' } }   # Microsoft trainable classifier
    return , $list
}

$plan = @(
    [ordered]@{ Policy = "$Prefix - External Email"; Location = 'Exchange'; Rules = @(
        [ordered]@{ Name = 'Code Sent to External Recipients'; Params = @{ AccessScope = 'NotInOrganization'; ContentContainsSensitiveInformation = (Get-SitList $minConf); GenerateAlert = $AlertRecipients; ReportSeverityLevel = 'High' } }) }
    [ordered]@{ Policy = "$Prefix - Endpoint"; Location = 'Endpoint'; Rules = @(
        [ordered]@{ Name = 'Code Pasted or Uploaded to Websites'; Params = @{ ContentContainsSensitiveInformation = (Get-SitList $minConf); GenerateAlert = $AlertRecipients; ReportSeverityLevel = 'High'
                    EndpointDlpRestrictions = @(@{ Setting = 'PasteToBrowser'; Value = 'Audit' }, @{ Setting = 'CloudEgress'; Value = 'Audit' }) } }
        [ordered]@{ Name = 'Code Copied Off Device'; Params = @{ ContentContainsSensitiveInformation = (Get-SitList '85'); ReportSeverityLevel = 'Low'
                    EndpointDlpRestrictions = @(@{ Setting = 'CopyPaste'; Value = 'Audit' }, @{ Setting = 'NetworkShare'; Value = 'Audit' }, @{ Setting = 'RemovableMedia'; Value = 'Audit' }) } }) }
)
if ($IncludeAttachmentAudit) {
    $plan += [ordered]@{ Policy = "$Prefix - External Attachments"; Location = 'Exchange'; Rules = @(
        [ordered]@{ Name = 'External Email With Attachment'; Params = @{ AccessScope = 'NotInOrganization'; DocumentSizeOver = '1B'; ReportSeverityLevel = 'Low' } }) }
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

    "== Plan (mode: $Mode, code SIT confidence: $Confidence, alerts to: $($AlertRecipients -join ', '))"
    "SITs used: $($wanted -join ', ')" + $(if ($IncludeSourceCodeClassifier) { ', Source code (Microsoft classifier)' } else { '' })
    foreach ($p in $plan) {
        $exists = [bool](Get-DlpCompliancePolicy -Identity $p.Policy -ErrorAction SilentlyContinue)
        $p.Exists = $exists
        "`nPolicy: $($p.Policy)  [$($p.Location)]" + $(if ($exists) { '  -> ALREADY EXISTS, will be skipped' } else { '' })
        foreach ($r in $p.Rules) {
            $acts = if ($r.Params.EndpointDlpRestrictions) { ($r.Params.EndpointDlpRestrictions | ForEach-Object { "$($_.Setting)=$($_.Value)" }) -join ', ' } else { 'audit' }
            "  rule: $($r.Name)  | actions: $acts | alert: $(if ($r.Params.GenerateAlert) { 'yes' } else { 'no (log only)' })"
        }
    }
    if (-not $Apply) { "`nPREVIEW ONLY. Nothing changed. Re-run with -Apply to create these policies."; return }
    if (-not $Force -and (Read-Host "`nType YES to create the policies above") -cne 'YES') { "Cancelled. Nothing changed."; return }

    foreach ($p in ($plan | Where-Object { -not $_.Exists })) {
        try {
            $locParams = if ($p.Location -eq 'Exchange') { @{ ExchangeLocation = 'All' } } else { @{ EndpointDlpLocation = 'All' } }
            New-DlpCompliancePolicy -Name $p.Policy -Mode $Mode @locParams -Comment 'Created by New-CodeDlpPolicies.ps1 (custom code SITs).' | Out-Null
            "Created policy: $($p.Policy)"
            foreach ($r in $p.Rules) {
                $prm = $r.Params.Clone()
                try { New-DlpComplianceRule -Name $r.Name -Policy $p.Policy @prm -ErrorAction Stop | Out-Null; "  created rule: $($r.Name)" }
                catch {
                    if ($IncludeSourceCodeClassifier -and $prm.ContentContainsSensitiveInformation) {
                        Write-Warning "  rule '$($r.Name)' failed with the classifier included ($($_.Exception.Message.Split("`n")[0])). Retrying without it."
                        $prm.ContentContainsSensitiveInformation = @($prm.ContentContainsSensitiveInformation | Where-Object { -not $_.ClassifierType })
                        New-DlpComplianceRule -Name $r.Name -Policy $p.Policy @prm -ErrorAction Stop | Out-Null; "  created rule (without classifier): $($r.Name)"
                    } else { throw }
                }
            }
        } catch { "FAILED on policy '$($p.Policy)': $($_.Exception.Message)" }
    }
    "`nDone. Policies are in mode '$Mode'. Review matches in Activity explorer before switching to Enable:"
    "  Set-DlpCompliancePolicy -Identity '<policy name>' -Mode Enable"
}
finally { if (-not $SkipConnect) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } }
