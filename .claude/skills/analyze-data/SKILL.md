---
name: analyze-data
description: Build auditable research calculations and canonical tables with the configured Opus data analyst. Use for cleaning supplied datasets, reconciling sources, calculating approved measures, validating units and joins, creating evidence matrices, and generating machine-readable tables after collection is complete.
argument-hint: "[self-contained analytical specification with inputs, formulas, outputs, and checks]"
disable-model-invocation: true
model: claude-opus-4-8
effort: low
context: fork
agent: data-analyst
---

Execute this approved analytical specification:

$ARGUMENTS

Use only supplied evidence and registered project sources. Stop when evidence, definitions, formulas, or methodology decisions are missing. Return the analysis packet defined by the `data-analyst` agent.
