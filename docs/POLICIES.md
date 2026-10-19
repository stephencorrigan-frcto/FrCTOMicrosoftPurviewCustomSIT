# Using the SITs in DLP policies

## What `New-CodeDlpPolicies.ps1` creates

| Policy | Rule | Conditions | Actions |
|---|---|---|---|
| `<Prefix> - External Email` | Code Sent to External Recipients | code SIT match + recipient outside the organisation | audit, alert |
| `<Prefix> - Endpoint` | Code Pasted or Uploaded to Websites | code SIT match | PasteToBrowser = Audit, CloudEgress = Audit, alert |
| | Code Copied Off Device | code SIT match (High) | CopyPaste, NetworkShare, RemovableMedia = Audit, log only |
| `<Prefix> - External Attachments` (optional) | External Email With Attachment | recipient outside + attachment of 1 byte or more | log only |

Defaults: simulation mode (`TestWithoutNotifications`), no user notifications, nothing blocked. The script only creates new policies; it never edits or removes existing ones.

## Steps the script leaves to the portal

**Scope website rules to AI sites.** Without a scope, PasteToBrowser and CloudEgress apply to every site. In the rule, under *Service domain and browser activities*, choose the sensitive service domain group to restrict them to, for example the Microsoft-managed **Generative AI Websites** group (Endpoint DLP settings, *Browser and domain restrictions to sensitive data*).

**Log code opened by AI desktop apps.** Browser rules do not see native apps. To log when a desktop AI app opens a file containing code:

1. Endpoint DLP settings, *Restricted apps and app groups*: create a group (for example *AI desktop apps*) with the app executables. Add them to the group only, not to the global restricted apps list.
2. Add a separate rule (alerts off) to the endpoint policy: code SIT match, action *File activities for apps in restricted app groups* = Audit.

This captures file access by the app. Text typed or pasted directly into a desktop app is not inspected; the earlier copy to the clipboard is logged (CopyPaste), but not where it was pasted.

**Microsoft's Source code classifier.** `-IncludeSourceCodeClassifier` adds Microsoft's built-in trainable classifier to the rules. If your tenant rejects it in this form, the script retries without it; add it in the portal instead.

## Confidence

| Rule type | Suggested confidence for the code SITs | Why |
|---|---|---|
| AI paste / upload, cloud upload (audit) | Medium | Catches short notebook-style snippets; harness shows no non-code false positives at Medium for the language SITs. |
| Volume / copy-off-device rules | High | These count matches toward thresholds; Medium makes developer machines noisy. |
| External email (alerting) | High, or Medium if you accept more alerts | Alerts on every match. |

Review alert volume for a week after any change.

## Pairing with other SITs

Code rules often benefit from Microsoft's credential SITs (*Client Secret / Api Key*, *General Password*, connection strings, cloud access keys). Keep broad ones such as *General Password* at High to limit noise, and check each SIT you add is relevant: searching the SIT list for "key" or "address" returns unrelated national identifiers and address types.
