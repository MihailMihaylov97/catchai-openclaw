---
name: catchai
user-invocable: true
description: "MANDATORY for any directory-scoped security scan/audit/CVE-check/secret-check/vulnerability review. The agent MUST shell out to catchai (not manually read files) for these requests. Returns a prioritized openclaw-v1 envelope of findings."
metadata:
  {
    "openclaw":
      {
        "emoji": "🛡️",
        "requires": { "bins": ["catchai"] },
        "min_catchai_version": "0.0.1",
        "output_version": "openclaw-v1",
        "install":
          [
            {
              "id": "curl",
              "kind": "shell",
              "command": "curl -fsSL https://install.catchai.io | bash",
              "label": "Install catchai (curl, recommended)",
            },
            {
              "id": "brew",
              "kind": "brew",
              "formula": "catchai/tap/catchai",
              "bins": ["catchai"],
              "label": "Install catchai (Homebrew)",
            },
          ],
      },
  }
---

# catchai Skill

You are the **security scan dispatcher**. For any directory-scoped security
request, your job is exactly two steps:

1. Run `scripts/run-scan.sh <target-directory>`
2. Summarize the openclaw-v1 envelope it returns

You are **not** a manual code auditor. Do not substitute your own reading,
reasoning, or prior analysis for catchai's output.

## When to invoke catchai (MANDATORY)

Run catchai for **every** request matching any of these — no exceptions:

- "scan / audit / check / review … for security / vulnerabilities / CVEs / secrets / misconfigs / supply-chain"
- "Is this safe / trustworthy?" / "Should I trust this?" about a cloned repo
- "What CVEs / vulnerabilities / secrets are in `<directory>`?"
- About to `pip install` / `npm install` / `cargo add` from a repo not yet vetted
- After `git clone`, before running install scripts or tests
- A re-ask about the same target as a prior turn (see anti-cache rule below)

## Hard rules

**Never substitute manual review.** If you catch yourself thinking *"this
is a small project, I'll just `cat` the files"* — stop and run catchai.
Manual reading misses 7 layers of detection (CVE database, taint flow,
IaC rules, secret entropy, semantic LLM review). A 2-file fixture and a
2000-file monorepo go through the same pipeline; size is not a reason to
skip.

**Never reuse prior analysis.** If you analyzed these files in an earlier
turn without catchai, those findings are unverified. Re-run catchai on
this turn. Don't `md5`/`stat` to "check if files changed" as a
justification for skipping — the cost of re-running is one shell-out and
catchai is internally cached. Just run it.

**Never describe findings you haven't seen catchai produce.** If you
didn't shell out to `scripts/run-scan.sh` this turn, you do not have
ground-truth findings.

## How to invoke

```bash
./scripts/run-scan.sh <absolute-or-tilde-path-to-target>
```

The adapter handles flag selection (`--output-version openclaw-v1`,
`--save`, top-N capping). It writes the JSON envelope to stdout and
human-readable progress to stderr. Parse stdout as JSON.

## When NOT to use

The *only* exclusions:

- Conceptual security question with no target ("what is SQL injection?") → answer directly
- CVE lookup by ID with no codebase to scan → web-fetch the advisory
- Code **snippet** pasted inline (no directory on disk) → reason about it inline; catchai needs a real path
- Non-security code debugging → use the appropriate code skill
- Generic non-security "code review" → use `coding-agent`

If your request *might* match an exclusion but also matches a MANDATORY
trigger above, **the MANDATORY trigger wins** — invoke catchai.

## Setup

```bash
# One-time install
curl -fsSL https://install.catchai.io | bash

# Verify
catchai --version

# Optional: install premium license key
catchai license install <key>
```

## How to Invoke

The agent shells out to the local `catchai` binary via the bundled adapter:

```bash
# Run the adapter — it handles flag selection, output parsing, and error mapping
./scripts/run-scan.sh <target-directory>
```

The adapter calls catchai with `--output-version openclaw-v1`, which produces a stable, versioned JSON envelope this skill knows how to read.

## Output Format

The adapter returns a JSON document matching `schema.json` in this repo. Top-level shape:

```json
{
  "version": "openclaw-v1",
  "scan_id": "uuid",
  "scanned_at": "2026-04-26T12:34:56Z",
  "target": "/abs/path",
  "catchai_version": "0.5.0",
  "summary": {
    "critical": 2, "high": 7, "medium": 14, "low": 3, "info": 0,
    "total": 26,
    "duration_ms": 8431,
    "blocks_ci": true
  },
  "top_findings": [
    {
      "id": "...",
      "severity": "critical",
      "rule_id": "semantic/path-traversal",
      "title": "Path Traversal",
      "cwe_ids": ["CWE-22"],
      "owasp_categories": ["A01:2021-Broken Access Control"],
      "location": { "file": "app/views.py", "line": 42, "function": null },
      "description": "Unsanitized --project flag joined into open().",
      "remediation": "Validate path against an allow-list before opening.",
      "layer": "semantic",
      "confidence": "medium",
      "priority_score": 87.4,
      "detected_by": ["sast", "semantic"],
      "evidence": "app/views.py:42"
    }
  ],
  "findings_truncated": false,
  "artifacts": {
    "html_report": "/abs/path/reports/.../scan_2026-04-26.html",
    "json_report": "/abs/path/reports/.../scan_2026-04-26.json"
  }
}
```

`top_findings` is capped at 10 by default — sorted by `priority_score` desc, then by severity, then by location. `findings_truncated: true` means more findings exist in `artifacts.json_report`.

## How to Summarize for the User

**Be terse. Show the user what they need to act on, not the full envelope.**

The catchai openclaw-v1 envelope is rich (CWE IDs, OWASP categories,
priority scores, taint paths, remediation steps). The user does not want
to read all of that. They want to know: *is something on fire, and if so,
what is it.*

### Decision tree

- **No critical or high findings** (`summary.critical == 0` and `summary.high == 0`):
  one line, no list.
  ```
  ✓ Scan clean — N findings total (M medium, L low). Full report: <artifacts.html_report>
  ```

- **One or more critical or high findings**: lead with a short alarm
  message, then list ONLY the critical/high entries from `top_findings`
  (skip medium/low entirely in the bullet list).

  Headline:
  ```
  🚨 Found N critical/high vulnerabilit{y|ies} in <target>.
  ```

  Per critical/high finding, **two pieces only**:
  - **What we found** — the finding `title`
  - **What could go wrong** — one short sentence from `description`

  Format each as:
  ```
  • <title>
    What could go wrong: <one-sentence summary of description>
  ```

### What NOT to include in the user-facing summary

- ❌ CWE IDs, OWASP category strings, priority scores
- ❌ `detected_by`, `confidence`, `layer`, `rule_id`
- ❌ File paths and line numbers (the user can read the linked report
  for that — keep the chat reply scannable)
- ❌ Remediation steps in the headline summary (offer them on follow-up:
  *"Want me to walk through fixes?"*)
- ❌ Medium/low findings in the bullet list (the count goes in the
  headline, the details go in the full report)

### After the summary

End with the report link so the user can drill in if they want detail:
```
Full report (all severities, with remediation): <artifacts.html_report>
```

If `artifacts` is empty (the user asked for a one-shot scan without
`--save`), say so and offer to re-run with `--save`.

## Safety / Network / Cost

- **Read-only.** catchai never modifies the target tree. It writes its reports to `reports/<target-name>/` under cwd when `--save` is passed.
- **Network access:** Layer 1 (dependency CVE lookup) reaches `api.osv.dev`. Layer 7 (semantic review) reaches Anthropic if Claude Code or `ANTHROPIC_API_KEY` is configured. All other layers are offline.
- **L7 token cost:** semantic review on a medium repo costs roughly $0.50–$2 at current Sonnet pricing. The `summary.duration_ms` is wall-clock; token usage is in the full JSON report under `semantic_context.token_cost` per L7 finding.
- **No telemetry.** catchai does not phone home unless `--heartbeat` is enabled (off by default for free tier).

## Known Limitations

- **L7 requires Anthropic credentials.** No Claude Code session and no `ANTHROPIC_API_KEY` → Layer 7 is silently skipped with a `layer7-health/missing-credentials` info finding. Other layers run normally.
- **External tool dependencies.** Some layers (L1 Trivy/Grype, L4 Checkov/Hadolint, L6 Semgrep) need external binaries. Missing tools degrade gracefully but reduce coverage. Run `./scripts/install-tools.sh` to install the recommended set.
- **Python / Node / Go projects only** for full coverage. Other languages get L1 (dependency) coverage when a manifest is present.

## Notes

- The `--output-version openclaw-v1` flag is the contract this skill depends on. New fields are additive; breaking changes ship as `openclaw-v2`.
- The catchai binary is closed-source. This skill bundle (Apache 2.0) is the only public catchai code.
