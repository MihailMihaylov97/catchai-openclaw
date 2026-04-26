# catchai — OpenClaw skill

Multi-layer security scanner integration for [OpenClaw](https://openclaw.com).
Run `catchai scan` from inside an OpenClaw conversation; get prioritized
findings the agent summarizes for you.

This repo is **the public glue** — markdown, JSON schema, and shell adapters.
The catchai scanner itself is closed-source and ships as a precompiled binary
(see [Install](#install)).

---

## Install

### 1. Install the catchai binary

```bash
curl -fsSL https://install.catchai.io | bash
```

Verify:

```bash
catchai --version
```

### 2. Install this skill bundle

#### Workspace install (per-user, fastest)

```bash
git clone https://github.com/MihailMihaylov97/catchai-openclaw \
    ~/.openclaw/workspace/skills/catchai
```

Then restart your OpenClaw gateway.

#### ClawHub install (when published)

```bash
openclaw skill install catchai
```

### 3. (Optional) Install external scanner tools

Some catchai layers shell out to external scanners (`semgrep`, `trivy`,
`checkov`, `hadolint`). Install the recommended set:

```bash
~/.openclaw/workspace/skills/catchai/scripts/install-tools.sh
```

The script asks the catchai binary which tools it wants, then uses
`brew` / `apt` / `pacman` to install them.

---

## Use

In any OpenClaw conversation:

> "scan this repo for vulnerabilities"

> "audit the security of `~/code/my-app`"

> "I just cloned this — is it safe?"

The agent invokes the skill, runs catchai against the project root,
summarizes the top findings, and points you at the full HTML report.

---

## What the agent sees

The skill returns a `openclaw-v1` JSON envelope (full schema in
[`schema.json`](./schema.json)) with:

- A severity-bucketed `summary` (critical/high/medium/low/info counts)
- The top 10 `findings` sorted by `priority_score` (one-line `evidence`
  per finding for direct quoting)
- Absolute paths to the saved `html_report` / `json_report` for deeper
  drill-down

The shape is **versioned and frozen** — `openclaw-v1` will never lose
fields. New capabilities ship as `openclaw-v2` without breaking existing
skill installs.

---

## Configuration

Environment variables read by `scripts/run-scan.sh`:

| Variable | Default | Effect |
|---|---|---|
| `CATCHAI_SEMANTIC` | `0` | Set to `1` to enable Layer 7 (LLM semantic review). Costs $0.50–$2 per scan at current pricing. |
| `CATCHAI_TOP_N` | `10` | Cap on `top_findings` in the envelope (0–100). |

LLM credentials for Layer 7 are auto-discovered: catchai uses the
local Claude Code session if available, falls back to `ANTHROPIC_API_KEY`
in the env, falls back to skipping L7 with a clean health finding.
**No `catchai login` flow.**

---

## Repository contents

```
catchai-openclaw/
├── SKILL.md                    OpenClaw agent contract — the file the agent reads
├── schema.json                 JSON Schema for the openclaw-v1 envelope
├── scripts/
│   ├── run-scan.sh             Adapter the agent invokes
│   └── install-tools.sh        Bootstrap external scanner tools
├── fixtures/
│   ├── vulnerable-python-app/  Known-vulnerable test target
│   └── clean-app/              Known-clean test target
├── tests/
│   └── contract_test.sh        Schema validation + frontmatter sanity
├── README.md                   This file
└── LICENSE                     Apache 2.0 (skill bundle only)
```

---

## License

The contents of this repository are licensed under the **Apache License,
Version 2.0** (see [`LICENSE`](./LICENSE)).

> **The catchai binary is NOT licensed under Apache 2.0.** It is
> proprietary closed-source software distributed under a separate
> commercial license. This repository contains only the public OpenClaw
> integration glue (SKILL.md, JSON schema, shell adapters, fixtures).
> No catchai detection logic, rules, prompts, or scanner internals are
> shipped here.

---

## Security

If you find a security issue in this skill bundle (the public glue):
open a GitHub issue or email security@catchai.io.

For vulnerabilities in the catchai scanner binary itself, see
[security.txt](https://catchai.io/.well-known/security.txt).

---

## Contributing

PRs welcome on:
- `SKILL.md` triggers (true positives we miss, false positives we should suppress)
- `scripts/run-scan.sh` (better error messages, additional flags)
- `scripts/install-tools.sh` (more package managers, tool-version pins)
- `fixtures/` (more diverse test targets)
- `tests/contract_test.sh` (additional invariants)

PRs that try to reverse-engineer the catchai binary, ship detection
logic, or include rule sets will be closed.
