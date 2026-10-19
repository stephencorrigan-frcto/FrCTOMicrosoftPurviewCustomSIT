# Code detection SITs for Microsoft Purview

Custom sensitive information types (SITs) that detect source code, with scripts to build, test, import and use them in DLP policies.

This is the **code-sits** branch of the custom SIT library. Other SIT families live on their own branches (see `main`).

**Deploying to a customer? Double-click `Deploy.cmd`.** A Windows app walks you through sign-in, settings, a preview of every change and the deployment. See [Deploy with the app](docs/DEPLOYER.md).

**Deploying for the first time? Follow the [full setup guide](docs/SETUP.md)**: prerequisites, device onboarding, browsers, Endpoint DLP settings, SITs, policies, portal steps, field testing and go-live.

## What's here

| Folder | Contents |
|---|---|
| `definitions/code-sits.json` | The SIT definitions: one primary regex, named supporting regexes and confidence patterns per SIT. **Edit this file**, then rebuild. |
| `sits/` | Importable rule packages built from the definitions: `code-sits-stable.xml` and `code-sits-experimental.xml`. |
| `scripts/Build-RulePack.ps1` | Builds the rule packages and rejects regex constructs the Purview validator refuses. |
| `scripts/Import-CustomSITs.ps1` | Adds or updates a rule package in a tenant (preview, then type YES). |
| `scripts/Export-CustomSITs.ps1` | Read-only export of a tenant's custom rule packages. |
| `scripts/New-CodeDlpPolicies.ps1` | Creates email and endpoint DLP policies that use the SITs (preview by default, simulation mode). |
| `Deploy.cmd`, `scripts/Start-Deployer.ps1` | The deployer app: sign in, choose settings, preview, deploy. Saves per-customer settings to `profiles\` (git-ignored). |
| `scripts/Build-Release.ps1` | Builds the customer download: a zip with only the runtime files, optionally code-signed, with checksums. |
| `scripts/Invoke-CodeSitDeployment.ps1` | Runs every tenant step in order with one sign-in (SIT backup, SIT import, app group, policies). Used by the app; also works on its own. |
| `scripts/New-EndpointDlpAppGroup.ps1` | Creates or extends an Endpoint DLP restricted app group (default *AI desktop apps* with `claude.exe`), keeping all existing groups, with a backup and restore script. |
| `tests/Test-CodeSITs.ps1` | Offline harness: scores the rule packages against the sample corpora in case-sensitive and case-insensitive mode. |
| `tests/samples/` | 268 code samples (10 languages) and 84 non-code samples, in six sets. All synthetic. |
| `tests/manual/` | Files for hands-on testing (paste into an AI site, attach to email, copy to USB) and `TEST-PLAN.md` with expected results. |
| `docs/` | [Full setup guide](docs/SETUP.md), [design](docs/DESIGN.md), [testing and results](docs/TESTING.md), [policies](docs/POLICIES.md). |

## The SITs

| SIT | Pack | Unseen-code result* | Non-code false positives* |
|---|---|---|---|
| Python Source Code | stable | 93% of Python samples at Medium or above | 0 |
| SQL Source Code | stable | 90% | 0 |
| Java Source Code | stable | 93% | 0 |
| JavaScript and TypeScript Source Code | stable | 94% | 0 |
| Source Code - Multi-language | stable | Breadth net for function/class/declaration code across languages | 0 |
| CSharp Source Code | experimental | 80% overall, 60% on the final blind set | 0 |
| PowerShell Script | experimental | 87% overall, 40% on the final blind set | 0 |
| C and C++ Source Code | experimental | 76% overall, 40% on the final blind set | 0 |
| Go Source Code | experimental | 90% overall, 60% on the final blind set | 0 |
| Bash and Shell Script | experimental | 77% overall, 20% on the final blind set | 0 |
| Source Code - Structural | experimental | 74% of all code (language-agnostic safety net) | 1 case-sensitive, 3 case-insensitive (log lines, semicolon lists) |

\* From `tests/Test-CodeSITs.ps1` across all 352 samples. All SITs together (any one matching) catch **256 of 268** code samples at Medium or above and **83%** of the final blind set. See [TESTING.md](docs/TESTING.md) for how the sets were built and why the blind numbers matter more.

**Realistic expectation:** whole files and longer snippets are caught reliably; short one- to three-line fragments are not. Regex SITs cannot learn general code shape. Pair them with Microsoft's built-in *Source code* trainable classifier in your DLP rules.

## Quick start

**With the app (recommended for customer deployments):** double-click `Deploy.cmd`, sign in, fill in the four steps, *Preview changes*, then *Deploy*. Details: [docs/DEPLOYER.md](docs/DEPLOYER.md).

**From PowerShell:**

```powershell
# 1. Build the rule packages from the definitions
.\scripts\Build-RulePack.ps1 -Maturity all

# 2. Test them offline
.\tests\Test-CodeSITs.ps1
.\tests\Test-CodeSITs.ps1 -Set blind4 -ShowMisses

# 3. Import the stable pack into your tenant (preview, then type YES)
.\scripts\Import-CustomSITs.ps1 -AdminUpn admin@contoso.com

# 4. Preview, then create, the DLP policies (simulation mode)
.\scripts\New-CodeDlpPolicies.ps1 -AdminUpn admin@contoso.com -AlertRecipients secops@contoso.com
.\scripts\New-CodeDlpPolicies.ps1 -AdminUpn admin@contoso.com -AlertRecipients secops@contoso.com -IncludeSourceCodeClassifier -Apply
```

Requirements: Windows PowerShell 5.1 or PowerShell 7, the `ExchangeOnlineManagement` module, and a role that can manage DLP (for example Compliance Administrator).

## Before you rely on these

1. **Check case sensitivity in your tenant.** Run `tests/manual/16_case_sensitivity_ALL_CAPS.py` through the Purview SIT test tool against *Python Source Code*. A match means Purview matches regexes case-insensitively; the stable pack is clean in both modes, but the experimental *Structural* SIT relies on case.
2. **Test in the Purview SIT test tool** with the files in `tests/manual/` and with your own non-code documents. The offline harness uses .NET regex, which is close to but not identical to Purview's engine.
3. **Run policies in simulation first** and review Activity explorer before enabling.

## Updating a SIT

1. Edit `definitions/code-sits.json`.
2. `.\scripts\Build-RulePack.ps1 -Version 1.1.0.0` (higher than the version in the tenant).
3. `.\tests\Test-CodeSITs.ps1 -ShowMisses` and check nothing regressed, especially non-code false positives.
4. `.\scripts\Import-CustomSITs.ps1 -AdminUpn ...` (updates in place).
