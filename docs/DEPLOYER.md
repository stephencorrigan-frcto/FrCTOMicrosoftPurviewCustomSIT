# Deploy with the app

`Deploy.cmd` opens a Windows app that deploys the code SITs, the AI desktop app group and the DLP policies to a customer's Microsoft 365 tenant. It covers steps 4, 6 and 7 of the [full setup guide](SETUP.md); the device, browser, portal and testing steps still apply.

## Before you start

- Windows with Windows PowerShell 5.1 (built in) or PowerShell 7.
- The `ExchangeOnlineManagement` module. If it is missing, the app shows an **Install module** button (installs for the current user from the PowerShell Gallery).
- An admin account in the customer's tenant with **Compliance Administrator** (or a role group that manages DLP policies and sensitive info types).
- Get the release ZIP (`CodeDlpDeployer-<version>.zip`) and extract it anywhere. The app clears Windows' downloaded-file mark from its own folder when it starts. Windows SmartScreen may still warn about `Deploy.cmd` the first time: *More info*, *Run anyway*.

## Steps

1. **Double-click `Deploy.cmd`.** A console window opens behind the app; leave it open.
2. **Sign in.** Optionally type the admin's username, then **Sign in**. Microsoft's own sign-in window asks for the username, password and MFA. The app never sees the password. The header then shows the tenant domain; a red dot means the account cannot manage DLP.
3. **Choose the settings.**
   | Section | Choice |
   |---|---|
   | Detection rules | The stable pack is always deployed. Tick the experimental pack for C#, PowerShell, C/C++, Go and Bash (less tested; see [TESTING.md](TESTING.md)). |
   | AI desktop apps | Group name and apps, one per line as `Display name = executable`. Check each executable on a device first (Task Manager, *Details*). Untick to skip. |
   | DLP policies | Alert recipients, policy name prefix, confidence, mode (simulation by default), Microsoft's *Source code* classifier, external attachment logging. |
4. **Preview changes.** Every step runs in preview against the tenant and the plan is shown in *Activity*. Nothing changes. A warning that the SITs are "not in the tenant yet" is expected on a first deployment: they are imported before the policies are created.
5. **Deploy.** The app confirms the tenant and the changes, then runs them in order:
   1. backs up the custom SITs already in the tenant,
   2. imports the SIT packs (skipped if the tenant already has this version),
   3. creates or updates the app group (existing groups are kept and backed up, with a restore script),
   4. creates the policies (existing policies with the same name are skipped, never changed).

   If a step fails, the later steps are skipped. Deploy only uses the settings you last previewed: change anything and you need to preview again.
6. **Finish in the portal.** Follow [SETUP.md](SETUP.md) step 8 (scope the website rule to AI sites, add the desktop-app rule), then the field tests in step 9.

## Files it writes

| Where | What |
|---|---|
| `exports\<domain>-<date-time>\` | `deploy.log`, `sit-backup\` (the tenant's custom rule packs before the change), `DlpAppGroups-backup-*.json` and `Restore-DlpAppGroups-*.ps1` |
| `profiles\<name>.json` | Settings saved with **Save settings**, to reuse for the next deployment or customer. No credentials are stored. |

Both folders are git-ignored because they contain customer details.

## Several customers

Sign in, deploy, then **Switch tenant** to sign in to the next customer. Keep one saved settings file per customer (for example `profiles\contoso.com.json`) and **Load settings** before previewing.

## Building a release

```powershell
.\scripts\Build-Release.ps1 -Version 1.0.0                                    # unsigned
.\scripts\Build-Release.ps1 -Version 1.0.0 -CertificateThumbprint <thumbprint>  # scripts Authenticode-signed
```

Writes `dist\CodeDlpDeployer-<version>.zip` and a `.sha256` next to it. The zip holds only what is needed to deploy (app, deployment scripts, built rule packages, definitions, assets, docs, manual test files) plus `VERSION.txt` and `SHA256SUMS.txt`; the sample corpora, offline harness and `Build-RulePack.ps1` stay in the repo. Signing uses a code-signing certificate in your certificate store and a timestamp, so signatures outlive the certificate. Rebuild the rule packages first if the definitions changed. `dist\` is git-ignored.

## Without the app

The app runs `scripts\Invoke-CodeSitDeployment.ps1`, which you can also run directly:

```powershell
.\scripts\Invoke-CodeSitDeployment.ps1 -AlertRecipients secops@contoso.com                     # preview (sign-in prompt)
.\scripts\Invoke-CodeSitDeployment.ps1 -AlertRecipients secops@contoso.com -IncludeExperimental `
    -Apps @{ Name = 'Claude Desktop'; ExecutableName = 'claude.exe' } -Apply                    # preview, type YES, deploy
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Nothing happens after **Sign in** | The Microsoft sign-in window can open behind the app or the console. If the Windows sign-in broker fails, the app retries with a browser sign-in. |
| Red dot after sign-in | The account lacks DLP permissions in that tenant. Sign in with a Compliance Administrator. |
| Rule fails with the classifier ticked | The script retries that rule without Microsoft's classifier; add it in the portal ([SETUP.md](SETUP.md) step 8). |
| Need the details of a run | `exports\<domain>-<date-time>\deploy.log`, or **Save log** at any time. |
