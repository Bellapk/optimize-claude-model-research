#!/usr/bin/env python3
"""Verify Claude Code model routing from local JSONL transcripts.

This script reads metadata only and prints model names, message counts, agent
types, descriptions, and timestamps. It never prints prompts or responses.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Iterable


def project_slug(project: Path) -> str:
    return re.sub(r"[^A-Za-z0-9]", "-", str(project.resolve()))


def read_records(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(record, dict):
                yield record


def message_models(path: Path) -> Counter[str]:
    models: Counter[str] = Counter()
    for record in read_records(path):
        message = record.get("message")
        if isinstance(message, dict):
            model = message.get("model")
            if isinstance(model, str) and model != "<synthetic>":
                models[model] += 1
    return models


def agent_calls(path: Path) -> list[dict[str, str]]:
    calls: list[dict[str, str]] = []
    for record in read_records(path):
        message = record.get("message")
        if not isinstance(message, dict):
            continue
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") != "tool_use" or block.get("name") != "Agent":
                continue
            inputs = block.get("input")
            if not isinstance(inputs, dict):
                continue
            calls.append(
                {
                    "id": str(block.get("id", "")),
                    "type": str(inputs.get("subagent_type", "")),
                    "description": str(inputs.get("description", "")),
                    "model_override": str(inputs.get("model", "")),
                    "timestamp": str(record.get("timestamp", "")),
                }
            )
    return calls


def nested_strings(value: Any) -> Iterable[str]:
    """Yield string values without exposing or retaining their surrounding content."""
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from nested_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from nested_strings(item)


def agent_result_links(
    path: Path,
    calls: list[dict[str, str]],
    transcript_ids: set[str],
) -> dict[str, str]:
    """Map Agent tool-use IDs to transcript IDs found in their tool results."""
    agent_call_ids = {call["id"] for call in calls if call["id"]}
    links: dict[str, str] = {}
    for record in read_records(path):
        message = record.get("message")
        if not isinstance(message, dict):
            continue
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict) or block.get("type") != "tool_result":
                continue
            tool_use_id = str(block.get("tool_use_id", ""))
            if tool_use_id not in agent_call_ids:
                continue
            result_strings = tuple(nested_strings(block.get("content")))
            matches = [
                transcript_id
                for transcript_id in transcript_ids
                if any(transcript_id in value for value in result_strings)
            ]
            if len(matches) == 1:
                links[tool_use_id] = matches[0]
    return links


def latest_main_transcript(claude_home: Path, project: Path) -> Path:
    folder = claude_home / "projects" / project_slug(project)
    candidates = list(folder.glob("*.jsonl"))
    if not candidates:
        raise FileNotFoundError(
            f"No Claude Code transcript found for {project}\n"
            f"Expected project transcript directory: {folder}"
        )
    return max(candidates, key=lambda item: item.stat().st_mtime)


def format_models(models: Counter[str]) -> str:
    return ", ".join(f"{model} ({count} messages)" for model, count in models.items()) or "none"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify that Claude Code used different models for reasoning and collection."
    )
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument(
        "--claude-home",
        type=Path,
        default=Path.home() / ".claude",
    )
    parser.add_argument("--main-model", default="claude-fable-5")
    parser.add_argument("--collector-model", default="claude-opus-4-8")
    args = parser.parse_args()

    try:
        main_path = latest_main_transcript(args.claude_home, args.project)
    except FileNotFoundError as error:
        print(error, file=sys.stderr)
        return 1

    main_models = message_models(main_path)
    calls = agent_calls(main_path)
    session_subagents = main_path.with_suffix("") / "subagents"
    subagent_paths = sorted(
        session_subagents.glob("agent-*.jsonl"),
        key=lambda item: item.stat().st_mtime,
        reverse=True,
    )
    subagent_models = [(path, message_models(path)) for path in subagent_paths]
    transcripts_by_id = {
        path.stem.removeprefix("agent-"): (path, models)
        for path, models in subagent_models
    }
    result_links = agent_result_links(main_path, calls, set(transcripts_by_id))

    print(f"Project: {args.project.resolve()}")
    print(f"Session: {main_path.stem}")
    print(f"Main: {format_models(main_models)}")
    print("Agent calls:")
    if calls:
        for call in calls:
            override = call["model_override"] or "<frontmatter>"
            transcript_id = result_links.get(call["id"])
            if transcript_id:
                transcript_path, actual_models = transcripts_by_id[transcript_id]
                actual = f"{transcript_path.name}: {format_models(actual_models)}"
            else:
                actual = "unlinked"
            print(
                f"  - {call['type']} | model={override} | "
                f"actual={actual} | {call['description']} | {call['timestamp']}"
            )
    else:
        print("  - none")

    print("Subagent transcripts:")
    if subagent_models:
        for path, models in subagent_models:
            print(f"  - {path.name}: {format_models(models)}")
    else:
        print("  - none")

    has_main = args.main_model in main_models
    has_verified_collector = any(
        call["type"] == "data-collector"
        and call["id"] in result_links
        and args.collector_model
        in transcripts_by_id[result_links[call["id"]]][1]
        for call in calls
    )
    passed = has_main and has_verified_collector

    print()
    print(
        "PASS: reasoning and evidence collection used the configured model split."
        if passed
        else "NOT VERIFIED: the expected model split was not found in this session."
    )
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
