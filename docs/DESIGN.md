# Design

## How a SIT is evaluated

A Purview SIT pattern has one **primary** element (`IdMatch`) and optional **supporting** elements. A pattern reaches its confidence level when the primary matches and the required supporting elements match **within the proximity window** (300 characters either side here).

Every SIT in this repo uses two patterns:

| Level | Requirement |
|---|---|
| High (85) | primary + at least **2 different** supporting elements nearby |
| Medium (75) | primary + at least **1** supporting element nearby |

In the rule package this is `<IdMatch>` plus `<Any minMatches="2">` (or `"1"`) over the supporting `<Match>` elements. A DLP rule then chooses which confidence it accepts (for example "High" means 85 to 100).

## Design approach

The language SITs combine:

- **Primary: a broad vocabulary of language markers** in a code context (for example `using System;`, `@Override`, `const x =`, `func name(`, `#include <...>`, `Get-Something`). One of many is enough.
- **Supporting: generic code structure** shared across languages (statement endings, brace blocks, code operators, dotted method calls, control flow followed by `(`), plus a few language-specific extras. Real code shows several of these; prose almost never does.

This combination came out of five rounds of testing (see [TESTING.md](TESTING.md)). Earlier designs that listed whole-statement idioms as the primary pattern scored well on the samples they were written against and badly on new code. Generic structure as supporting evidence is what made the SITs generalise.

Lessons that are now rules in the definitions:

- **SQL** must look structural regardless of case: a real column list (`a, b`, `*`, `t.col`, `func(`, `x AS y`), `CREATE TABLE name (`, `MERGE ... USING`, `WITH x AS (SELECT`. Otherwise English such as "select a date from the calendar" matches when case is ignored.
- **Go `:=`** only counts with a code-like right-hand side (a call, `&`, `[]`, `make(`, a literal), and never as its own supporting evidence. Otherwise maths notation (`rate := annual rate / 12`) matches.
- **No token counts twice.** If the same text can satisfy the primary and a supporting element, the SIT fires on almost nothing.
- **`package`** must be `package name;` (Java) or `package name` at the end of a line (Go). Otherwise "Package pricing starts at..." matches when case is ignored.

## Purview regex rules

The Purview validator rejects patterns that "may perform poorly". In practice, avoid:

| Avoid | Use instead |
|---|---|
| `.*`, `.+`, `.{0,n}` inside groups | explicit character classes, for example `[\w\s,.()]*` |
| negated classes with a repeat, `[^)]*`, `[^\r\n]+` | explicit classes |
| ranged repeats `{3,}`, `{0,60}` | `[A-Z][A-Z][A-Z]+`, or restructure |
| repeated groups `(...)*`, `(...)+` | a single optional group `(...)?` or alternatives |

`Build-RulePack.ps1` checks for these before writing a package. Its check is an approximation: the real test is the import, which names the offending regex if it fails.

Other limits worth knowing: regexes over 1,024 characters are rejected, and a tenant can hold a limited number of custom rule packages, so related SITs share a package.

## Case sensitivity

Whether Purview matches these regexes case-sensitively should be confirmed in your tenant (`tests/manual/16_case_sensitivity_ALL_CAPS.py`). The harness scores both modes. The stable pack has no non-code false positives in either mode. The experimental *Structural* SIT uses camelCase and snake_case identifiers as evidence, which only works if matching is case-sensitive.

## What regex SITs cannot do

Regex SITs recognise patterns; they cannot learn what code looks like in general. Expect misses on very short fragments with no distinctive marker (for example `count=$((count + 1))`, `prices[:3]`, `int days[12] = {...}`). Microsoft's built-in *Source code* trainable classifier complements them, and endpoint controls are the backstop.
