---
name: execute-research-plan
description: Execute an approved research plan by routing each step to the configured Opus collector, Opus data analyst, Sonnet research worker, or main reasoning context. Use after Plan mode has produced and the user has approved a plan. Enforce dependencies, serial execution, model boundaries, and fail-closed behavior.
argument-hint: "[approved plan text or path to the approved plan]"
disable-model-invocation: true
allowed-tools: Agent
---

Execute this approved research plan:

$ARGUMENTS

Before execution, normalize the plan into this ledger:

| ID | Dependency | Class | Agent | Input | Output | Acceptance check |
|---|---|---|---|---|---|---|

Use this routing map:

- `JUDGMENT` -> main Fable context; only research design, logic, methodology, evidence conflicts, claim selection, and final approval.
- `COLLECTION` -> `data-collector` on its configured Opus model.
- `ANALYSIS` -> `data-analyst` on its configured Opus model for calculations and canonical tables.
- `EXECUTION` -> `research-worker` on its configured Sonnet model for code, charts, edits, documents, formatting, and mechanical QA.

Execute only ready steps and run one subagent at a time. Give each agent a self-contained brief and never override its model or effort. Pass compact outputs forward; do not repeat searches, calculations, edits, or checks in the main context. Never use Workflow, Explore, Plan, general-purpose, or unnamed agents.

When the approved plan names an execution Skill such as `craft-research-writing`, include that exact Skill name in the `research-worker` brief. Let the Sonnet worker load it instead of executing it in the main Fable context.

If a step is ambiguous, missing evidence, or requires an unapproved judgment, stop that step and report the precise blocker. Never fall back to Fable for delegated execution.

Finish with the ledger updated to `complete`, `partial`, or `blocked` for every step, followed by only the unresolved Fable judgment items.
