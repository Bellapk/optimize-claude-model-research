# Research model-routing policy

Use the main Fable 5 context only for work that materially requires high-level judgment:

- Formulating research questions and hypotheses
- Designing the research plan or methodology
- Causal, economic, statistical, or conceptual reasoning
- Reconciling genuinely conflicting evidence
- Scenario construction and sensitivity reasoning
- Final synthesis, conclusions, writing, and critical review

Delegate retrieval-dominated work proactively to the `data-collector` subagent:

- Web, literature, dataset, and source searches
- Reading long reports, papers, policy documents, documentation, or local files
- Extracting tables, statistics, dates, definitions, quotations, and metadata
- Checking units, frequencies, geographic scope, coverage periods, publication dates, and revisions
- Compiling citations, provenance, source-quality notes, and evidence inventories

For a mixed research task:

1. Use Fable 5 to define the question and write a self-contained collection brief with scope, dates, geography, variables, units, and required source types.
2. Delegate that brief to `data-collector` without overriding its configured model.
3. Run one collector at a time. Do not parallelize collectors unless the user explicitly prioritizes speed over token usage.
4. Accept the returned evidence packet as the retrieval record. Do not repeat its searches or reread long sources in the Fable context.
5. Use Fable 5 only to interpret the evidence, resolve conceptual issues, and produce the final result.
6. If follow-up collection is necessary, send one narrow brief covering only the unresolved evidence gap.

If `data-collector` cannot run with {{COLLECTOR_MODEL}}, report that collection is blocked. Do not silently collect with Fable 5, an inherited model, or a general-purpose subagent. Never fabricate evidence to bypass a collection failure.

The user can force an isolated collection run with `/collect-data <self-contained evidence requirement>` or by mentioning `@"data-collector (agent)"`.
