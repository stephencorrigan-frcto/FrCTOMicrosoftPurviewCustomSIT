# Microsoft Purview custom SIT library

A library of custom sensitive information types (SITs) for Microsoft Purview DLP, with the scripts and tests to build, validate and deploy them.

Each SIT family lives on its own branch, with the same layout, so families can be developed and released independently.

## Branches

| Branch | SIT family |
|---|---|
| [`code-sits`](../../tree/code-sits) | Source code detection: Python, SQL, Java, JavaScript/TypeScript, multi-language, plus experimental C#, PowerShell, C/C++, Go, Bash and a language-agnostic structural SIT. |

## Layout of a SIT branch

| Folder | Contents |
|---|---|
| `definitions/` | The SIT definitions (JSON), the single source of truth. |
| `sits/` | Rule packages (XML) built from the definitions, ready to import. |
| `scripts/` | Build, import, export and policy-creation scripts. |
| `tests/` | Offline test harness, sample corpora and manual test files with expected results. |
| `docs/` | Design notes, test method and results, policy guidance. |

## Principles

- Definitions are generic: no organisation names, domains or tenant identifiers.
- Every SIT is tested against code and non-code samples, in case-sensitive and case-insensitive mode, including sets never used for tuning.
- Scripts that change a tenant preview first and ask for confirmation.

Test any SIT in your own tenant (Purview SIT test tool, then DLP simulation mode) before relying on it.
