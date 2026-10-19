<#
.SYNOPSIS
  Sends test emails with code samples (as attachments, in the body, or both) to check the email DLP rule.

.DESCRIPTION
  Sends one email per sample and format from -Sender to -Recipients through Microsoft Graph (sendMail), then
  writes sent.csv with each subject, so you can find the messages in Activity explorer and the audit log.
  Subjects look like "[DLP test 20261019-1105] 04_csharp_class.cs (attachment)".

  Sign-in: Connect-MgGraph with Mail.Send and Mail.Send.Shared. Sign in as the sender, or as an account with
  Send As permission on the sender mailbox. Send to a recipient outside the organisation to exercise the
  "Code Sent to External Recipients" rule. Use dummy content only: the samples in tests\manual are synthetic.

  Policies take about an hour to apply after a change; matches appear in Activity explorer within one to two hours.

.PARAMETER Samples
  Files to send: paths, FileInfo objects, or objects with Path and Expected (Expected is copied to sent.csv).
  Default: every sample in tests\manual.

.PARAMETER Format
  Attachment, Body, or Both (two emails per sample).

.EXAMPLE
  .\Send-DlpTestEmails.ps1 -Sender alex@contoso.com -Recipients test@outside.example
  .\Send-DlpTestEmails.ps1 -Sender alex@contoso.com -Recipients test@outside.example -Format Both -Samples (Get-ChildItem ..\tests\manual\0*.py)
#>
param(
    [Parameter(Mandatory)][string]$Sender,
    [Parameter(Mandatory)][string[]]$Recipients,
    [object[]]$Samples = @(Get-ChildItem (Join-Path $PSScriptRoot '..\tests\manual') -File | Where-Object { $_.Name -ne 'TEST-PLAN.md' }),
    [ValidateSet('Attachment', 'Body', 'Both')][string]$Format = 'Attachment',
    [string]$SubjectPrefix = 'DLP test',
    [string]$RunId = (Get-Date -Format 'yyyyMMdd-HHmm'),
    [string]$TenantId,
    [int]$DelaySeconds = 2,
    [switch]$Force,
    [switch]$SkipConnect,
    [string]$OutDir = (Join-Path $PSScriptRoot ('..\exports\dlp-test-' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
)
$ErrorActionPreference = 'Stop'

$items = foreach ($s in $Samples) {
    $path = if ($s -is [string]) { $s } elseif ($s.FullName) { $s.FullName } else { [string]$s.Path }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Sample not found: $path" }
    [pscustomobject]@{ Path = (Resolve-Path -LiteralPath $path).Path; Name = [IO.Path]::GetFileName($path); Expected = [string]$s.Expected }
}
if (-not $items) { throw 'No samples to send.' }
$formats = if ($Format -eq 'Both') { @('attachment', 'body') } else { @($Format.ToLower()) }

"== Plan: $(@($items).Count * $formats.Count) email(s) from $Sender to $($Recipients -join ', ') ($($formats -join ' + '))"
foreach ($i in $items) { "  $($i.Name)" + $(if ($i.Expected) { "   ($($i.Expected))" } else { '' }) }

if (-not $SkipConnect) {
    Import-Module Microsoft.Graph.Authentication
    $c = @{ Scopes = @('Mail.Send', 'Mail.Send.Shared'); NoWelcome = $true }; if ($TenantId) { $c.TenantId = $TenantId }
    Connect-MgGraph @c
}
$ctx = Get-MgContext
if (-not $ctx) { throw 'Not signed in to Microsoft Graph. Run Connect-MgGraph -Scopes Mail.Send, Mail.Send.Shared, or omit -SkipConnect.' }
"Signed in to Graph as $($ctx.Account)"
if (-not $Force -and (Read-Host "`nType YES to send these emails") -cne 'YES') { "Cancelled. Nothing sent."; return }

New-Item -ItemType Directory -Force $OutDir | Out-Null
$to = @($Recipients | ForEach-Object { @{ emailAddress = @{ address = $_ } } })
$rows = @(); $failed = 0; $n = 0
foreach ($i in $items) {
    $text = [IO.File]::ReadAllText($i.Path)
    foreach ($f in $formats) {
        $n++
        $subject = "[$SubjectPrefix $RunId] $($i.Name) ($f)"
        $msg = @{ subject = $subject; toRecipients = $to }
        if ($f -eq 'body') {
            $msg.body = @{ contentType = 'Text'; content = "DLP test sample $($i.Name), pasted below. Synthetic content for data loss prevention testing.`r`n`r`n$text" }
        } else {
            $msg.body = @{ contentType = 'Text'; content = "DLP test sample $($i.Name) attached. Synthetic content for data loss prevention testing." }
            $msg.attachments = @(@{ '@odata.type' = '#microsoft.graph.fileAttachment'; name = $i.Name; contentType = 'text/plain'
                                    contentBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($i.Path)) })
        }
        $body = @{ message = $msg; saveToSentItems = $true } | ConvertTo-Json -Depth 8
        $status = 'Sent'; $err = ''
        try {
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$([Uri]::EscapeDataString($Sender))/sendMail" -Body $body -ContentType 'application/json' | Out-Null
            "  sent      $subject"
        } catch {
            $status = 'Failed'; $failed++
            $err = $_.Exception.Message.Split("`n")[0]
            if ($err -match 'ErrorSendAsDenied|AccessDenied|Forbidden') { $err += " ($($ctx.Account) needs Send As on $Sender, or sign in as $Sender)" }
            "  FAILED    $subject : $err"
        }
        $rows += [pscustomobject]@{ Time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); RunId = $RunId; File = $i.Name; Format = $f
                                    Subject = $subject; Sender = $Sender; Recipients = ($Recipients -join '; '); Expected = $i.Expected; Status = $status; Error = $err }
        if ($DelaySeconds -gt 0 -and $n -lt (@($items).Count * $formats.Count)) { Start-Sleep -Seconds $DelaySeconds }
    }
}
$csv = Join-Path $OutDir 'sent.csv'
$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
"`nSent $($rows.Count - $failed) of $($rows.Count). Record: $((Resolve-Path $csv).Path)"
"Find them in Activity explorer (activity: DLP rule matched) or the audit log (record type ComplianceDLPExchange) by searching for '$SubjectPrefix $RunId'. Allow one to two hours."
if ($failed) { throw "$failed email(s) failed to send. See the FAILED lines above." }
