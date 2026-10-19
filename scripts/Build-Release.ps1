<#
.SYNOPSIS
  Builds the customer download: a zip with only the files needed to run the deployer, optionally code-signed.

.DESCRIPTION
  Copies the runtime files (Deploy.cmd, the deployment scripts, the built rule packages, definitions, assets,
  docs and the manual test files) into dist\CodeDlpDeployer-<version>\, writes VERSION.txt and SHA256SUMS.txt,
  and zips it to dist\CodeDlpDeployer-<version>.zip with a .sha256 file next to it.

  Left out: the sample corpora, the offline test harness and Build-RulePack.ps1 (they are for editing SITs,
  not deploying them), plus exports\ and profiles\.

  With -CertificateThumbprint every .ps1 is Authenticode-signed (with a timestamp, so signatures stay valid
  after the certificate expires) and checked before zipping. Deploy.cmd cannot be signed; it starts the app
  with -ExecutionPolicy Bypass, so signing is for integrity and trust, not to get past execution policy.

.EXAMPLE
  .\scripts\Build-Release.ps1
  .\scripts\Build-Release.ps1 -Version 1.1.0 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
#>
param(
    [string]$Version,
    [string]$CertificateThumbprint,
    [string]$TimestampServer = 'http://timestamp.digicert.com',
    [string]$OutDir = (Join-Path $PSScriptRoot '..\dist')
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$commit = (& git -C $root rev-parse --short HEAD 2>$null)
$dirty = [bool](& git -C $root status --porcelain 2>$null)
if (-not $Version) { $Version = (Get-Date -Format 'yyyy.MM.dd') + $(if ($commit) { "-$commit" } else { '' }) }
if ($dirty) { Write-Warning 'The working tree has uncommitted changes; they are included in this build.' }

$cert = $null
if ($CertificateThumbprint) {
    $cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -CodeSigningCert |
        Where-Object { $_.Thumbprint -eq $CertificateThumbprint.Replace(' ', '').ToUpper() } | Select-Object -First 1
    if (-not $cert) { throw "No code-signing certificate with thumbprint $CertificateThumbprint in CurrentUser\My or LocalMachine\My." }
    if ($cert.NotAfter -lt (Get-Date)) { throw "Certificate $($cert.Subject) expired on $($cert.NotAfter)." }
}

# runtime files, relative to the repo root (folders are copied whole)
$include = @(
    'Deploy.cmd', 'README.md',
    'scripts\Start-Deployer.ps1', 'scripts\Invoke-CodeSitDeployment.ps1', 'scripts\Import-CustomSITs.ps1',
    'scripts\Export-CustomSITs.ps1', 'scripts\New-CodeDlpPolicies.ps1', 'scripts\New-EndpointDlpAppGroup.ps1',
    'sits', 'definitions', 'assets', 'docs', 'tests\manual'
)
foreach ($x in @('sits\code-sits-stable.xml', 'sits\code-sits-experimental.xml')) {
    if (-not (Test-Path (Join-Path $root $x))) { throw "$x is missing. Run scripts\Build-RulePack.ps1 -Maturity all first." }
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path   # full path, so relative names below line up
$name = "CodeDlpDeployer-$Version"
$stage = Join-Path $OutDir $name
$zip = Join-Path $OutDir "$name.zip"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
if (Test-Path $zip) { Remove-Item $zip -Force }
New-Item -ItemType Directory -Force $stage | Out-Null

foreach ($rel in $include) {
    $src = Join-Path $root $rel
    if (-not (Test-Path $src)) { throw "Missing from the repo: $rel" }
    $dst = Join-Path $stage $rel
    New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
    Copy-Item $src $dst -Recurse -Force
}
"Copied $(@(Get-ChildItem $stage -Recurse -File).Count) files to $stage"

if ($cert) {
    "Signing scripts with $($cert.Subject) (expires $($cert.NotAfter.ToString('yyyy-MM-dd')))"
    foreach ($f in Get-ChildItem $stage -Recurse -Filter *.ps1) {
        $sig = Set-AuthenticodeSignature -FilePath $f.FullName -Certificate $cert -TimestampServer $TimestampServer -HashAlgorithm SHA256
        if ($sig.Status -ne 'Valid') { throw "Signing failed for $($f.Name): $($sig.Status) $($sig.StatusMessage)" }
        "  signed $($f.FullName.Substring($stage.Length + 1))"
    }
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllLines((Join-Path $stage 'VERSION.txt'), [string[]]@(
    "Netrio Code DLP Deployer $Version"
    "Commit: $(if ($commit) { $commit } else { 'unknown' })$(if ($dirty) { ' (with uncommitted changes)' } else { '' })"
    "Built: $((Get-Date).ToString('yyyy-MM-dd HH:mm'))"
    "Signed: $(if ($cert) { $cert.Subject } else { 'no' })"
), $utf8)
$sums = foreach ($f in Get-ChildItem $stage -Recurse -File | Sort-Object FullName) {
    "$((Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower())  $($f.FullName.Substring($stage.Length + 1).Replace('\', '/'))"
}
[IO.File]::WriteAllLines((Join-Path $stage 'SHA256SUMS.txt'), [string[]]$sums, $utf8)

Compress-Archive -Path $stage -DestinationPath $zip
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText("$zip.sha256", "$hash  $name.zip`n", $utf8)
"`nRelease: $zip ($([math]::Round((Get-Item $zip).Length / 1KB)) KB)"
"SHA-256: $hash"
if (-not $cert) { 'Not signed. Pass -CertificateThumbprint to sign the scripts.' }
