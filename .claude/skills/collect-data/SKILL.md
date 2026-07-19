---
name: collect-data
description: Collect and verify research data, primary sources, literature, statistics, tables, metadata, citations, and supporting evidence without producing final analysis or conclusions.
argument-hint: "[self-contained research question or evidence requirement]"
disable-model-invocation: true
model: claude-opus-4-8
effort: low
context: fork
agent: data-collector
---

Collect evidence for this self-contained request:

$ARGUMENTS

Follow these rules:

1. Search primary and authoritative sources before secondary summaries.
2. Extract only evidence relevant to the request.
3. Verify publication dates, coverage periods, definitions, units, frequencies, geography, and revision status.
4. Record a direct URL or precise local file location for every material finding.
5. Identify conflicting figures, methodology differences, missing observations, and comparability limits.
6. Return `partial` or `blocked` when the request cannot be completed; never invent missing evidence.
7. Do not modify files, run nested agents, write final research conclusions, or turn the evidence into finished prose.

Return the evidence packet defined by the `data-collector` agent. Keep it concise enough for the parent reasoning context to analyze without repeating the underlying searches.
