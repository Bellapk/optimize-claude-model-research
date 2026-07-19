---
name: route-research
description: Route mixed research requests, continuation prompts, reviewer comments, figure work, writing revisions, analytical tables, and evidence gaps across the main reasoning model, Opus collection and analysis agents, and the Sonnet research worker. Use before taking tool actions when a task combines reasoning, retrieval, reading, calculation, coding, plotting, editing, document generation, or QA.
argument-hint: "[research request, continuation instruction, or reviewer comments]"
allowed-tools: Agent
---

Route this request before executing it:

$ARGUMENTS

1. Split the request into atomic blocks and label each block `JUDGMENT`, `COLLECTION`, `ANALYSIS`, or `EXECUTION`.
2. Keep only research design, logic, methodology, evidence-conflict resolution, claim selection, and final approval in the main reasoning context.
3. Delegate every search, long-document read, source check, citation task, or new factual measure to `data-collector` without overriding its model.
4. Delegate every approved calculation, reconciliation, derived measure, evidence matrix, and canonical analytical table to `data-analyst` without overriding its model.
5. Delegate every file scan, code or shell task, chart build from canonical tables, document generation, scoped prose revision, formatting task, or mechanical QA check to `research-worker` without overriding its model.
6. If the user names an execution Skill such as `craft-research-writing`, include that exact Skill name in the `research-worker` brief so the Sonnet worker loads it.
7. For mixed blocks, run `data-collector`, then `data-analyst` when needed, then `research-worker`.
8. Run only one subagent at a time. Never use Workflow, Explore, Plan, general-purpose, or unnamed agents for delegated work.
9. Do not repeat a subagent's searches, reads, calculations, edits, or checks in the main context.
10. If the configured agent or model is unavailable, stop that block. Never fall back to the main reasoning model.
