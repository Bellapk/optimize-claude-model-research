#!/usr/bin/env python3
"""Verify Claude Code model routing from local JSONL transcript metadata."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path


def project_slug(project: Path) -> str:
    return re.sub(r"[^A-Za-z0-9]", "-", str(project.resolve()))


def records(path: Path):
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def model_counts(path: Path) -> Counter[str]:
    counts: Counter[str] = Counter()
    for record in records(path):
        message = record.get("message")
        if isinstance(message, dict):
            model = message.get("model")
            if model and model != "<synthetic>":
                counts[str(model)] += 1
    return counts


def agent_calls(path: Path) -> list[dict[str, str]]:
    calls: list[dict[str, str]] = []
    for record in records(path):
        message = record.get("message")
        content = message.get("content") if isinstance(message, dict) else None
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            if block.get("name") != "Agent" or not isinstance(block.get("input"), dict):
                continue
            tool_input = block["input"]
            calls.append(
                {
                    "type": str(tool_input.get("subagent_type", "")),
                    "description": str(tool_input.get("description", "")),
                    "override": str(tool_input.get("model", "")),
                    "timestamp": str(record.get("timestamp", "")),
                }
            )
    return calls


def latest_main_transcript(project_dir: Path) -> Path:
    candidates = list(project_dir.glob("*.jsonl"))
    if not candidates:
        raise FileNotFoundError(f"No main-session JSONL files found in {project_dir}")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prove that Claude Code used different models for reasoning and collection."
    )
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument(
        "--claude-home", type=Path, default=Path.home() / ".claude"
    )
    parser.add_argument("--main-model", default="claude-fable-5")
    parser.add_argument("--collector-model", default="claude-opus-4-8")
    args = parser.parse_args()

    project_dir = args.claude_home / "projects" / project_slug(args.project)
    try:
        main_transcript = latest_main_transcript(project_dir)
    except FileNotFoundError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    main_counts = model_counts(main_transcript)
    calls = agent_calls(main_transcript)
    collector_calls = [call for call in calls if call["type"] == "data-collector"]
    subagent_dir = project_dir / main_transcript.stem / "subagents"
    subagent_files = sorted(
        subagent_dir.glob("agent-*.jsonl"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    ) if subagent_dir.exists() else []
    subagent_models = [(path, model_counts(path)) for path in subagent_files]

    print(f"Project: {args.project.resolve()}")
    print(f"Session: {main_transcript.stem}")
    print("Main-session models:")
    for model, count in main_counts.most_common():
        print(f"  {model}: {count} assistant messages")

    print("Data-collector calls:")
    if collector_calls:
        for call in collector_calls:
            override = call["override"] or "none (frontmatter controls the model)"
            print(
                f"  {call['timestamp']} | {call['description']} | override: {override}"
            )
    else:
        print("  none found")

    print("Subagent transcript models:")
    if subagent_models:
        for path, counts in subagent_models:
            summary = ", ".join(f"{model}: {count}" for model, count in counts.items())
            print(f"  {path.name}: {summary or 'no model metadata'}")
    else:
        print("  none found")

    collector_seen = any(
        counts.get(args.collector_model, 0) > 0 for _, counts in subagent_models
    )
    passed = (
        main_counts.get(args.main_model, 0) > 0
        and bool(collector_calls)
        and collector_seen
    )
    if passed:
        print(
            f"PASS: {args.main_model} handled the main session and "
            f"{args.collector_model} handled data collection."
        )
        return 0

    print("NOT VERIFIED: expected model split was not found in the latest session.")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
