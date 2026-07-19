# Research model-routing policy

Route every research request by capability before taking tool actions. Treat continuation prompts, numbered reviewer comments, and “start from where you left off” as new routing decisions.

## Model boundaries

Keep the main Fable 5 context only for work that materially requires judgment:

- Research questions, hypotheses, methodology, and plan design
- Causal, economic, statistical, or conceptual reasoning
- Reconciling genuinely conflicting evidence
- Scenario construction, claim selection, and sensitivity reasoning
- Final synthesis, conclusions, and approval of the research argument

Delegate evidence work to `data-collector` using {{COLLECTOR_MODEL}} with low effort:

- Web, literature, dataset, and source searches
- Long reports, papers, policies, documentation, and source-file reading
- Tables, statistics, dates, definitions, quotations, and metadata extraction
- Units, coverage, publication dates, revisions, citations, and provenance checks
- Any reviewer comment asking for a measure, number, source, verification, or missing evidence

Delegate data analysis to `data-analyst` using {{ANALYST_MODEL}} with low effort:

- Cleaning and reconciling supplied datasets
- Approved formulas, ratios, bridges, unit conversions, and derived measures
- Canonical machine-readable tables and evidence matrices
- Join, denominator, range, duplicate-key, and reconciliation validation
- Tables requested by reviewer comments after their evidence and methodology are defined

Delegate production work to `research-worker` using {{WORKER_MODEL}} with low effort:

- Repository scans, routine local-file reading, code, and shell commands
- File edits, charts from canonical tables, figures, logos, document generation, and build tasks
- Drafting or revising prose under an approved argument and evidence brief
- Citation formatting, style checks, consistency sweeps, rendering, tests, and mechanical QA

## Mandatory routing sequence

1. In Plan mode, split the request into `JUDGMENT`, `COLLECTION`, `ANALYSIS`, and `EXECUTION` steps. Give every step an ID, dependencies, agent, inputs, output, and acceptance check. Classify every numbered comment separately.
2. Use Fable 5 only to define unresolved questions and create self-contained briefs.
3. Run `data-collector` first when evidence is missing. Accept its evidence packet without repeating searches or rereading long sources.
4. Pass approved formulas, definitions, evidence packets, output paths, and validation checks to `data-analyst` for calculations and canonical tables.
5. Pass approved claims, canonical tables, target files, constraints, and acceptance checks to `research-worker`.
6. If the user names an execution Skill such as `craft-research-writing`, pass that exact Skill name to `research-worker`; do not load and execute it in the Fable context.
7. Review the returned packets. Use Fable 5 only for unresolved judgment and final approval; do not redo an agent's tool loop.

## Cost and safety constraints

- Run only one subagent at a time. Do not launch parallel workers unless the user explicitly prioritizes speed over usage.
- Use only the named `data-collector`, `data-analyst`, and `research-worker` agents. Do not use Workflow, Explore, Plan, general-purpose, or unnamed agents for delegated research work because they can inherit Fable 5.
- The Fable 5 context must not perform WebSearch, WebFetch, long-document reading, data calculation, table building, bulk file scans, routine Edit/Write operations, plotting, builds, or mechanical QA.
- Do not override an agent's configured model or effort.
- If `data-collector` cannot run with {{COLLECTOR_MODEL}}, stop collection. If `data-analyst` cannot run with {{ANALYST_MODEL}}, stop analysis. If `research-worker` cannot run with {{WORKER_MODEL}}, stop execution. Never fall back to Fable 5.
- Never fabricate evidence or silently make a research judgment to bypass a blocked route.

Use `/execute-research-plan <approved plan>` after Plan mode. Use `/route-research <mixed request>` to force classification, `/collect-data <evidence brief>` for Opus collection, `/analyze-data <analytical specification>` for Opus tables, and `/execute-research <execution brief>` for Sonnet execution. A slash command is recognized only when it begins the message.
