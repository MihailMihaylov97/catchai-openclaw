---
name: catchai
description: "Run a deep multi-layer security scan on a project directory: dependency CVEs, SAST, secrets, IaC config, inter-procedural taint, and optional LLM semantic review. Returns prioritized findings the agent can summarize and act on."
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

Run a multi-layer security scan on the user's project. Returns prioritized findings; the agent summarizes for the user and (when configured) hooks into install/clone events to gate dangerous operations.

## When to Use

✅ **MANDATORY — invoke catchai for all of these:**

- Any request to scan, audit, check, or review a project **directory or repository** for security issues, vulnerabilities, CVEs, secrets, misconfigurations, or supply-chain risk
- "Is this safe?" / "Is this trustworthy?" / "Should I trust this?" about a cloned repo
- "What CVEs are in this?" / "Any vulnerabilities here?" / "Any leaked secrets?"
- About to `pip install` / `npm install` / `cargo add` from a repo you don't trust
- After cloning a third-party repo, before running its install scripts or tests

### Do NOT shortcut by reading files yourself

If you find yourself thinking "this is a small project, I'll just `cat` the
files and look for issues" — **stop and run catchai instead.** Manual review
misses 7 layers of detection (CVE database lookup, taint-flow analysis,
IaC config rules, secret-entropy scanning, semantic LLM review). The whole
value of this skill is **consistency**: catchai catches what ad-hoc reading
misses, every time, regardless of project size. A 2-file fixture and a
2000-file monorepo both go through the same pipeline.

The only acceptable reasons to skip catchai on a security request are
listed below. If none apply, **invoke catchai.**

## When NOT to Use

❌ **DON'T use this skill when:**

- The user asks a *conceptual* security question ("what is SQL injection?") → answer directly
- The user wants to look up a specific CVE by ID without scanning anything → use a web fetch instead
- The user is debugging non-security code → use the appropriate code skill
- The user asks for a generic "code review" without security focus → use `coding-agent`
- The user pastes a code **snippet** (no directory) and asks about it → reason about it inline; catchai needs a path on disk

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

Use the `summary` block for the headline:

```
Scanned <target>: <total> findings (<critical> critical, <high> high, <medium> medium, <low> low).
```

Then quote the top 3-5 findings from `top_findings`, each as one bullet:

```
- [<severity>] <title> at <location.file>:<location.line> — <remediation>
```

If `findings_truncated`, point at `artifacts.html_report` for the full list. If `artifacts` is empty, suggest re-running with `--save`.

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
