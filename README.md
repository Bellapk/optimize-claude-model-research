<div align="center">

# Claude Research Router

### Plan with your strongest model. Execute every step with the right one.

[![Claude Code](https://img.shields.io/badge/Claude_Code-compatible-6B4FBB)](https://code.claude.com/docs)
[![Three-tier routing](https://img.shields.io/badge/routing-Fable%20%7C%20Opus%20%7C%20Sonnet-2E8B57)](#the-routing-model)
[![Windows, macOS, Linux](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-0078D4)](#quick-start)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**A plan-first, capability-based model router for serious research in Claude Code.**

Keep **Fable 5** focused on research design and judgment. Route source collection to low-effort **Opus 4.8**, analytical tables to medium-effort **Opus 4.8**, and code, figures, document builds, scoped revisions, and mechanical QA to medium-effort **Sonnet**.

If this keeps your strongest model thinking instead of searching, calculating, and rebuilding charts, consider giving the project a star.

</div>

---

## Why this exists

A research task is rarely one task. A single prompt may contain methodology, web searches, PDF reading, calculations, tables, plotting, reviewer comments, document generation, and final synthesis. Claude Code can launch agents and workflows, but generic workers often inherit the expensive main model.

That creates two problems:

1. The flagship context spends its budget on repetitive tool loops.
2. Long searches, file scans, and build output crowd out the reasoning that actually needs the strongest model.

Claude Research Router turns an approved research plan into a serial execution pipeline with explicit model boundaries.

## The routing model

| Task class | Default context | Typical work |
|---|---|---|
| `JUDGMENT` | Fable 5 main context | Questions, methodology, logic, conflicts, claim selection, final approval |
| `COLLECTION` | Opus 4.8 `data-collector` | Search, long-document reading, source verification, citations, missing evidence |
| `ANALYSIS` | Opus 4.8 `data-analyst` | Cleaning, reconciliation, calculations, derived measures, canonical tables |
| `EXECUTION` | latest Sonnet `research-worker` | Code, charts, edits, documents, formatting, tests, mechanical QA |

```mermaid
flowchart LR
    A["Research request"] --> B["Fable 5 Plan mode"]
    B --> C["Approved task ledger"]
    C -->|"COLLECTION"| D["Opus 4.8 data-collector"]
    D -->|"evidence packet"| E["Opus 4.8 data-analyst"]
    E -->|"canonical tables"| F["Sonnet research-worker"]
    F -->|"files + verification packet"| G["Fable 5 final judgment"]

    style B fill:#6B4FBB,color:#fff
    style D fill:#2E8B57,color:#fff
    style E fill:#2E8B57,color:#fff
    style F fill:#0078D4,color:#fff
    style G fill:#6B4FBB,color:#fff
```

Agents run one at a time by default. The policy prohibits generic `Workflow`, `Explore`, `Plan`, and `general-purpose` workers for delegated research execution because they can inherit the main Fable model.

## What you get

- A concise global routing policy for mixed tasks and reviewer comments.
- An automatically invocable `/collect-data` Skill backed by a read-only Opus collector.
- An Opus `data-analyst` for calculations, reconciliation, evidence matrices, and canonical tables.
- A Sonnet `research-worker` for code, charts, files, document generation, revisions, and QA.
- `/execute-research-plan` to execute an approved Plan-mode task ledger serially.
- Deterministic manual commands for each execution tier.
- Fail-closed behavior when a configured model or required evidence is unavailable.
- A transcript verifier that recursively inspects ordinary agents and hidden workflow workers.
- Safe, idempotent installers that preserve existing `CLAUDE.md` content and back up conflicting files.

## Quick start

### 1. Clone

```bash
git clone https://github.com/Bellapk/optimize-claude-model-research.git
cd optimize-claude-model-research
```

### 2. Install globally

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

macOS, Linux, or WSL:

```bash
chmod +x install.sh
./install.sh
```

The installer adds:

```text
~/.claude/
├── CLAUDE.md
├── agents/
│   ├── data-collector.md
│   ├── data-analyst.md
│   └── research-worker.md
└── skills/
    ├── route-research/SKILL.md
    ├── collect-data/SKILL.md
    ├── analyze-data/SKILL.md
    ├── execute-research/SKILL.md
    └── execute-research-plan/SKILL.md
```

Conflicting files are backed up under:

```text
~/.claude/backups/optimize-claude-model-research/<timestamp>/
```

The installer does not change the main session model or overwrite unrelated settings.

### 3. Restart and check

Restart Claude Code, then run:

```text
/doctor
/memory
/skills
/agents
```

Expected:

- `/agents` lists `data-collector`, `data-analyst`, and `research-worker`.
- The collector shows Opus 4.8 with low effort.
- The analyst shows Opus 4.8 with medium effort.
- The worker shows the `sonnet` alias with medium effort.
- `/skills` lists the five router commands.

## Recommended Plan-mode workflow

### Step 1: plan with Fable

Ask Fable 5 in Plan mode to produce this ledger:

```text
For every plan step include:
ID, dependency, task class, assigned agent, required inputs,
expected output, and acceptance check.

Classes:
JUDGMENT, COLLECTION, ANALYSIS, EXECUTION.
Do not execute yet.
```

Review and approve the plan. Research judgment stays yours and Fable's; mechanical execution does not.

### Step 2: execute the approved plan

Send the command as the beginning of its own message:

```text
/execute-research-plan <paste the approved plan or provide its path>
```

The executor resolves dependencies, runs one named agent at a time, passes compact outputs forward, and returns a completion ledger.

### Step 3: let Fable review only the unresolved judgment

Fable receives evidence, analytical, and execution packets. It should not repeat searches, calculations, edits, or tests.

## Manual commands

### Evidence collection: Opus 4.8

```text
/collect-data Quantify China's corn feed use from 2018-2025. Collect primary
sources, definitions, units, revision dates, URLs, conflicts, and missing evidence.
```

### Calculations and tables: Opus 4.8

```text
/analyze-data Using the supplied evidence packet and raw CSV files, calculate
corn import intensity and build outputs/tables/corn_intensity.csv. Preserve source
and derived columns and validate units, denominators, missing years, and totals.
```

### Code, figures, files, and QA: Sonnet

```text
/execute-research Using the approved canonical tables, update Figures 3 and 8,
apply assets/logo.png, rebuild the DOCX, and run the style and render checks.
Do not change claims, numbers, or caveats.
```

### Mixed request routing

```text
/route-research Apply these reviewer comments. Collect missing evidence first,
build the required analytical table, update the figures and prose, then return
only unresolved research judgments for final approval.
```

Claude Code recognizes a slash command only when it begins the message. Do not embed `/collect-data` or `/execute-research-plan` after ordinary prose or combine multiple slash commands on one line.

## Automatic versus deterministic routing

The `collect-data` and `route-research` descriptions are visible to Claude, so it can invoke them automatically when a request matches. The global policy also tells the main model which named agent to choose.

Automatic routing is still a model decision. The manual commands are deterministic because their `context: fork`, `agent`, and `model` frontmatter pins the execution context. For high-cost work, use `/execute-research-plan` or one of the tier-specific commands.

## Verify the models that actually ran

UI labels are helpful; transcript metadata is stronger evidence.

Windows:

```powershell
py scripts\verify_routing.py --project "D:\path\to\research-project"
```

macOS, Linux, or WSL:

```bash
python3 scripts/verify_routing.py --project /path/to/research-project
```

Inspect only a recent interval:

```powershell
py scripts\verify_routing.py --project "D:\path\to\research-project" `
  --since "2026-07-19T15:52:35Z"
```

The verifier recursively inspects `subagents/**/agent-*.jsonl`, including dynamic workflow directories. It fails when:

- no configured Opus or Sonnet context ran,
- a named agent used the wrong model,
- an Agent call cannot be linked to its transcript, or
- any delegated transcript used the Fable main model.

It reads metadata only and never prints prompts, evidence, or responses.

## Customize model routing

Defaults:

- Collector: `claude-opus-4-8`
- Analyst: `claude-opus-4-8`
- Worker: `sonnet`

The official `sonnet` alias resolves to the latest Sonnet model available for the account and provider. This avoids hard-coding a model ID that may not be enabled everywhere. See Claude Code's [model configuration](https://code.claude.com/docs/en/model-config).

Windows:

```powershell
.\install.ps1 -CollectorModel opus -AnalystModel opus -WorkerModel sonnet
```

macOS, Linux, or WSL:

```bash
./install.sh --collector-model opus --analyst-model opus --worker-model sonnet
```

Preview without writing:

```powershell
.\install.ps1 -DryRun
```

The `CLAUDE_CODE_SUBAGENT_MODEL` environment variable can override agent frontmatter. The installers warn when they detect a conflicting value.

## Why not use one Skill or `opusplan`?

A single forked Skill selects one agent and one model. Reliable multi-model routing therefore needs separate agent contracts plus a routing policy.

Claude Code's `opusplan` switches models by interaction mode: Opus in Plan mode and Sonnet in execution mode. This project routes by research capability: evidence retrieval, analytical tables, production execution, and final judgment have distinct contexts, permissions, and return contracts.

## Safety and usage controls

- Only one subagent runs at a time by default.
- Generic inherited-model workflows are prohibited for delegated research work.
- The collector is read-only and cannot edit files or spawn agents.
- The analyst can create tables but cannot search the web or choose methodology.
- The worker can edit files but cannot search the web or spawn agents.
- Each agent has a bounded turn limit. Collection uses low effort; analysis and production use medium effort for more reliable calculations and multi-step deliverables.
- Missing evidence and unresolved research judgments fail closed.
- Fable does not repeat completed searches, calculations, edits, builds, or QA loops.

Claude Code permission behavior can still be affected by parent-session and organization settings. Review `/permissions` before using agents on sensitive repositories.

## Repository layout

```text
.
├── .claude/
│   ├── agents/
│   │   ├── data-collector.md
│   │   ├── data-analyst.md
│   │   └── research-worker.md
│   └── skills/
│       ├── collect-data/SKILL.md
│       ├── analyze-data/SKILL.md
│       ├── execute-research/SKILL.md
│       ├── route-research/SKILL.md
│       └── execute-research-plan/SKILL.md
├── templates/research-model-routing.md
├── scripts/verify_routing.py
├── tests/test_package.py
├── install.ps1
├── install.sh
└── LICENSE
```

## Run the package tests

```bash
python -m unittest discover -s tests -v
```

The tests validate models, effort, permissions, tool boundaries, manual and automatic Skill behavior, plan routing, packet contracts, installer coverage, and verifier compilation.

## GitHub About description

> Plan-first multi-model research routing for Claude Code: Fable for judgment, Opus for evidence and analytical tables, Sonnet for code, figures, documents, and QA—with transcript-level proof.

Suggested topics:

`claude-code` · `research` · `model-routing` · `subagents` · `agent-skills` · `llm` · `ai-agents` · `token-optimization` · `context-engineering` · `research-workflow`

## Author

**Kun Peng, Ph.D.** is a researcher and research-workflow builder focused on agricultural markets, quantitative analysis, and practical AI systems for evidence-based decision-making. He develops reproducible workflows that turn complex source material, data, and research questions into clear, decision-ready insights.

[Connect with Kun Peng on LinkedIn](https://www.linkedin.com/in/peng-kun/).

## License

[MIT](LICENSE) © 2026 Kun Peng
