# Testing and results

## The harness

`tests/Test-CodeSITs.ps1` loads the built rule packages (the same XML that gets imported), models Purview's evaluation (primary + supporting elements within the proximity window), and scores every SIT in **case-sensitive and case-insensitive** mode.

For each SIT it reports:

- **Own >=Medium / Own High**: share of samples in its own language(s) reaching 75 / 85. SITs marked `*` in the definitions (multi-language and structural) are scored against all code.
- **Non-code FP**: any match on a non-code sample, in each case mode.
- **ANY SIT**: share of all code samples caught by at least one SIT. DLP rules list several SITs with "any of these", so this is closest to real-world coverage.
- **Verdict**: PASS when own-language coverage is at least 80% at Medium or above and there are no non-code matches in either mode; otherwise REVIEW.

```powershell
.\tests\Test-CodeSITs.ps1                       # all sets, both packs
.\tests\Test-CodeSITs.ps1 -Set blind4 -ShowMisses
.\tests\Test-CodeSITs.ps1 -WritePlan            # refresh tests\manual\TEST-PLAN.md
```

The harness uses .NET regex. Purview uses a different engine, so treat the harness as a fast regression check and confirm in the Purview SIT test tool.

## The sample sets

All samples are synthetic, written for this project. The sets are in the order they were written, and the order matters:

| Set | Code | Non-code | Role |
|---|---|---|---|
| `build` | 76 | 26 | Written with the first definitions. |
| `holdout` | 48 | 12 | Harder styles, written after round 1. Exposed that round 1 had overfitted. |
| `blind1` | 32 | 10 | Written after round 2 was frozen. Exposed that idiom-listing does not generalise. |
| `blind2` | 32 | 10 | Written after round 3 was frozen (generic structure as supporting evidence). |
| `blind3` | 40 | 12 | Written after round 4 was frozen. |
| `blind4` | 40 | 14 | Written after round 5 (current) was frozen. **The only set never used for tuning.** |

Every set except `blind4` was used to fix something after it was scored, so results on those sets are optimistic. `blind4` is the honest estimate of performance on new code.

## Results (current definitions)

**All sets (352 samples):** all SITs together catch 256 of 268 code samples at Medium or above (234 at High). The stable pack has **no** non-code false positives in either case mode.

**Blind set 4 (never tuned against):**

| SIT | Own samples at Medium or above | Non-code FP (cs / ci) |
|---|---|---|
| SQL Source Code | 5/5 | 0 / 0 |
| Java Source Code | 4/5 | 0 / 0 |
| JavaScript and TypeScript Source Code | 4/5 | 0 / 0 |
| CSharp Source Code | 3/5 | 0 / 0 |
| Go Source Code | 3/5 | 0 / 0 |
| PowerShell Script | 2/5 | 0 / 0 |
| C and C++ Source Code | 2/5 | 0 / 0 |
| Bash and Shell Script | 1/5 | 0 / 0 |
| Source Code - Structural | 29/40 | 1 / 3 |
| **Any SIT** | **33/40 (83%)**, 28/40 at High | |

Python was not part of the blind sets; on its own 28-sample corpus *Python Source Code* reaches 26/28 at Medium or above.

## Trend across blind tests

Each round was frozen, then scored on a set written afterwards:

| Round | Design | Blind result (any SIT) |
|---|---|---|
| 2 | idiom-listing primaries | 53% (blind1) |
| 3 | language markers + generic structure | 78% (blind2) |
| 4 | grammar fixes | 58% (blind3, shorter snippets) |
| 5 | + language-agnostic structural SIT | 83% (blind4) |

Recall on unseen short snippets sits between roughly 55% and 85% depending on how short and idiomatic the snippets are. Precision on non-code text is consistently high for the language SITs.

## Manual tests

`tests/manual/` holds files for hands-on tests, and `TEST-PLAN.md` lists the confidence each SIT should reach for each file.

| Test | How |
|---|---|
| AI paste | Paste the file contents into an AI chat site in Edge (or Chrome with the Microsoft Purview extension) on an onboarded device. |
| Email | Attach the file, or paste it in the body, of an email to an external address. |
| Endpoint copy | Copy the file to a network share or removable drive. |
| Case sensitivity | Run `16_case_sensitivity_ALL_CAPS.py` through the Purview SIT test tool against *Python Source Code*. |

Use dummy content only: pasting into a public AI site sends the text to that service. File `12_fake_credentials.txt` contains only published documentation examples.

Results appear in the unified audit log under record type `ComplianceDLPEndpoint` (endpoint rule matches) and `ComplianceDLPExchange` (email rule matches), typically within one to two hours. Record type `DLPEndpoint` holds plain device file activity, not rule matches.
