# Full setup guide

End-to-end deployment of the code detection SITs and DLP policies in a Microsoft Purview tenant, from prerequisites to go-live. Steps marked **(portal)** have no supported script yet.

Every script that changes a tenant previews first and asks you to type `YES`. Run them in a test tenant, or in preview, before production.

| Step | What | How |
|---|---|---|
| 1 | Prerequisites | checks |
| 2 | Onboard and verify devices | portal / device checks |
| 3 | Browser coverage | Intune or Group Policy |
| 4 | Endpoint DLP settings and the AI desktop app group | `New-EndpointDlpAppGroup.ps1` + portal |
| 5 | Build and test the SITs offline | `Build-RulePack.ps1`, `Test-CodeSITs.ps1` |
| 6 | Import the SITs and check them in Purview | `Import-CustomSITs.ps1` + portal |
| 7 | Create the DLP policies (simulation) | `New-CodeDlpPolicies.ps1` |
| 8 | Portal touch-ups | portal |
| 9 | Field test | `tests/manual/` + audit log |
| 10 | Tune and go live | portal / `Set-DlpCompliancePolicy` |
| 11 | Maintain and roll back | scripts |

---

## 1. Prerequisites

- **Licensing**: Endpoint DLP and DLP alerting need the appropriate Microsoft 365 E5 / E5 Compliance (or equivalent) licences for the users in scope. Check Microsoft's current licensing guidance for your plan.
- **Role**: an account with Compliance Administrator (or a role group that can manage DLP policies and sensitive info types).
- **Auditing on**: DLP rule matches are recorded in the unified audit log.
  ```powershell
  Connect-ExchangeOnline -UserPrincipalName admin@contoso.com
  Get-AdminAuditLogConfig | Select-Object UnifiedAuditLogIngestionEnabled   # must be True
  ```
- **PowerShell**: Windows PowerShell 5.1 or PowerShell 7 with the module:
  ```powershell
  Install-Module ExchangeOnlineManagement -Scope CurrentUser
  ```
  The scripts connect with `Connect-IPPSSession` (Security & Compliance PowerShell) and sign out when done.

## 2. Onboard and verify devices

Endpoint rules only work on devices onboarded to Microsoft Purview / Microsoft Defender for Endpoint.

1. **(portal)** Onboard devices through Intune, Group Policy, a script or Defender for Endpoint (Purview portal, *Settings*, *Device onboarding*).
2. Verify on each device (or through your RMM tool) that both services are running:
   ```powershell
   Get-Service Sense, MDDlpSvc | Select-Object Name, Status, StartType
   ```
   `Sense` is the Defender for Endpoint sensor; `MDDlpSvc` is the Purview data loss prevention service. A device with either stopped will not evaluate endpoint rules.
3. **(portal)** In Endpoint DLP settings, keep *Always audit file activity for devices* on. It records file activity even without a rule match, which is what you investigate with.

Check onboarding for new devices too: an onboarding method that does not cover newly built machines leaves gaps that only show up as missing events.

## 3. Browser coverage

- **Microsoft Edge**: supported natively, nothing to install.
- **Google Chrome and Mozilla Firefox**: deploy the Microsoft Purview extension (Intune or Group Policy). Without it, pastes and uploads in those browsers are not inspected.

Check on a device: `chrome://extensions` should list *Microsoft Purview Extension*.

## 4. Endpoint DLP settings

**(portal)** Purview portal, *Settings*, *Data loss prevention*, *Endpoint DLP settings*.

| Setting | Recommendation |
|---|---|
| Advanced classification scanning and protection | Leave as it is. It is for exact data match and named entities and does not support *Paste to supported browsers*. |
| Sensitive service domain groups | Use the Microsoft-managed **Generative AI Websites** group for AI sites; no need to create one. Create your own groups for other site categories (for example unsanctioned cloud storage) if you want separate rules. |
| Restricted apps and app groups | Create an **AI desktop apps** group (below). Add apps to the group only, not to the global *Restricted apps* list, which has its own default action. |

**Create the AI desktop app group** with the script. It keeps every existing group, backs up the current list to `exports\`, previews, then asks for `YES`:

```powershell
.\scripts\New-EndpointDlpAppGroup.ps1 -AdminUpn admin@contoso.com                    # preview
.\scripts\New-EndpointDlpAppGroup.ps1 -AdminUpn admin@contoso.com -Apply             # create
.\scripts\New-EndpointDlpAppGroup.ps1 -AdminUpn admin@contoso.com -Apply `
    -Apps @{ Name = 'Claude Desktop'; ExecutableName = 'claude.exe' }, @{ Name = 'Another AI app'; ExecutableName = 'another.exe' }
```

Confirm each executable name on a device (Task Manager, *Details* tab) before adding it: a wrong name silently matches nothing. The group does nothing until a rule references it (step 8).

## 5. Build and test the SITs offline

```powershell
.\scripts\Build-RulePack.ps1 -Maturity all          # sits\code-sits-stable.xml and code-sits-experimental.xml
.\tests\Test-CodeSITs.ps1                           # all sample sets, both case modes
.\tests\Test-CodeSITs.ps1 -Set blind4 -ShowMisses   # the set never used for tuning
```

Deploy the **stable** pack first. Add the experimental pack only after reviewing its results in [TESTING.md](TESTING.md).

## 6. Import the SITs and check them in Purview

```powershell
.\scripts\Import-CustomSITs.ps1 -AdminUpn admin@contoso.com                                      # stable pack
.\scripts\Import-CustomSITs.ps1 -AdminUpn admin@contoso.com -RulePack .\sits\code-sits-experimental.xml   # optional
```

Then, in the Purview portal (*Data classification*, *Classifiers*, *Sensitive info types*), select each SIT and use **Test**:

1. Upload files from `tests/manual/` and compare with `tests/manual/TEST-PLAN.md`.
2. Upload a few of your own non-code documents (reports, contracts, emails) and confirm nothing matches.
3. Upload `tests/manual/16_case_sensitivity_ALL_CAPS.py` against *Python Source Code*. A match means Purview matches these regexes case-insensitively. The stable pack is clean in both modes; the experimental *Structural* SIT depends on case.

## 7. Create the DLP policies (simulation)

```powershell
.\scripts\New-CodeDlpPolicies.ps1 -AdminUpn admin@contoso.com -AlertRecipients secops@contoso.com                     # preview
.\scripts\New-CodeDlpPolicies.ps1 -AdminUpn admin@contoso.com -AlertRecipients secops@contoso.com `
    -IncludeSourceCodeClassifier -IncludeAttachmentAudit -Apply
```

This creates `Code DLP - External Email`, `Code DLP - Endpoint` and (optionally) `Code DLP - External Attachments` in simulation mode, all actions audit-only, no user notifications. See [POLICIES.md](POLICIES.md) for the rules.

## 8. Portal touch-ups

**(portal)** These need the Purview portal:

1. **Scope the website rule to AI sites.** Edit *Code DLP - Endpoint*, rule *Code Pasted or Uploaded to Websites*. Under *Service domain and browser activities*, set the sensitive service domain restriction to the **Generative AI Websites** group (Audit). Without this the rule applies to all sites.
2. **Log code opened by AI desktop apps.** Add a rule to *Code DLP - Endpoint*:
   - Name: `Code Opened by AI Desktop Apps`
   - Condition: content contains the code SITs (same list as the other rules)
   - Action: *Audit or restrict activities on devices*, *File activities for apps in restricted app groups*, add **AI desktop apps**, **Audit only**
   - Alerts **off**, user notifications **off** (a developer working with an AI app on a codebase would otherwise generate constant alerts)
3. **Optional: Microsoft's Source code classifier.** If `-IncludeSourceCodeClassifier` was not accepted by your tenant, add *Source code* (trainable classifier) to each rule's *Content contains* condition.

What desktop-app logging can and cannot see: file access by the app is logged; text typed or pasted directly into a desktop app is **not** inspected. The earlier copy to the clipboard is logged at the source (*Copy to clipboard*, audited by the copy-off-device rule), but not where it was pasted.

## 9. Field test

Wait about an hour after creating or changing policies so devices receive them. Then, on an onboarded device with dummy content only:

| Test | Do | Expected record |
|---|---|---|
| AI paste | Paste `tests/manual/02_python_snippet_no_imports.py` into an AI chat site in Edge | Activity type **PastedToBrowser**, target domain of the AI site, rule *Code Pasted or Uploaded to Websites* |
| AI desktop app | Open or attach a `tests/manual` file in the AI desktop app | Activity type **File accessed by unallowed app**, rule *Code Opened by AI Desktop Apps* |
| Email | Email `tests/manual/04_csharp_class.cs` (or code in the body) to an external address | Rule *Code Sent to External Recipients*, alert to the recipients |
| Copy off device | Copy a code file to a network share or USB drive | Rule *Code Copied Off Device* (logged, no alert) |
| Negative | Paste `tests/manual/13_plain_business_email.txt` | No rule match |

Where to look:

- **Activity explorer** (Purview portal, *Data loss prevention*), activity *DLP rule matched*.
- **Unified audit log**: record type `ComplianceDLPEndpoint` for endpoint rule matches and `ComplianceDLPExchange` for email rule matches. Record type `DLPEndpoint` holds plain device file activity, not rule matches.
- Records usually appear within one to two hours.

## 10. Tune and go live

1. Run in simulation for a week and review matches and volume.
2. Adjust confidence per rule (see [POLICIES.md](POLICIES.md)): Medium for the audit-only AI paste and upload rules (catches short notebook-style snippets), High for volume and copy-off-device rules.
3. Keep broad add-on SITs (for example *General Password*) at High, and remove any added by mistake.
4. Switch each policy on:
   ```powershell
   Set-DlpCompliancePolicy -Identity 'Code DLP - Endpoint' -Mode Enable
   ```

## 11. Maintain and roll back

| Task | How |
|---|---|
| Change a SIT | Edit `definitions/code-sits.json`, `Build-RulePack.ps1 -Version x.y.z.w` (higher than the tenant), `Test-CodeSITs.ps1`, `Import-CustomSITs.ps1` |
| Back up custom SITs | `.\scripts\Export-CustomSITs.ps1 -AdminUpn admin@contoso.com` (output in `exports\`, git-ignored) |
| Restore app groups | Run the `Restore-DlpAppGroups-*.ps1` written next to the backup in `exports\` |
| Remove a policy | `Remove-DlpCompliancePolicy -Identity 'Code DLP - Endpoint'` (removes its rules) |
| Remove the SITs | Remove them from all rules first, then `Remove-DlpSensitiveInformationTypeRulePackage -Identity <rule package id>` |

## Troubleshooting

| Symptom | Check |
|---|---|
| No endpoint rule matches at all | Device onboarded and both services running (step 2); an hour since the last policy change; the content reaches the rule's confidence (run the file through the SIT test tool) |
| Browser pastes not caught | Edge, or Chrome/Firefox with the Purview extension; rule scoped to a group that includes the site |
| Desktop AI app not logged | Executable name in the app group matches the process name; the rule references the group; only file access is logged, not pastes |
| Matches in the audit log but not in Activity explorer | Filters, date range and role permissions in Activity explorer |
| Rule pack import fails with "regular expression processor ... may perform poorly" | A regex uses a construct the validator rejects; `Build-RulePack.ps1` names the likely one; see [DESIGN.md](DESIGN.md) |
| Rule pack update refused | The XML version must be higher than the tenant's: `Build-RulePack.ps1 -Version x.y.z.w` |
| Too many alerts | Raise confidence to High on the noisy rule, or move it to log-only |
