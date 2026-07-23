---
name: execute-research
description: Execute a self-contained research production brief with the configured Sonnet worker: edit files, transform supplied data, build charts and tables, revise drafts, apply reviewer comments, format citations, generate documents, run tests, and perform mechanical QA. Use only after evidence and research judgments are defined.
argument-hint: "[self-contained execution brief with files, evidence, constraints, and acceptance checks]"
disable-model-invocation: true
model: sonnet
effort: medium
context: fork
agent: research-worker
---

Execute this self-contained research production brief:

$ARGUMENTS

Use only the evidence, claims, files, and constraints supplied in the brief or already registered in the project. If new evidence or a research judgment is required, stop and return the smallest blocker instead of searching, guessing, or silently deciding it.

Return the execution packet defined by the `research-worker` agent.
