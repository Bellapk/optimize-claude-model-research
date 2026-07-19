#!/usr/bin/env python3
"""Verify Claude Code model routing from local JSONL metadata.

The verifier prints model names, message counts, agent types, descriptions,
timestamps, and transcript paths. It never prints prompts or responses.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from datetime import datetime
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


def parse_timestamp(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def record_is_in_range(record: dict[str, Any], since: datetime | None) -> bool:
    if since is None:
        return True
    timestamp = parse_timestamp(str(record.get("timestamp", "")))
    return timestamp is not None and timestamp >= since


def message_models(path: Path, since: datetime | None = None) -> Counter[str]:
    models: Counter[str] = Counter()
    for record in read_records(path):
        if not record_is_in_range(record, since):
            continue
        message = record.get("message")
        if isinstance(message, dict):
            model = message.get("model")
            if isinstance(model, str) and model != "<synthetic>":
                models[model] += 1
    return models


def agent_calls(
    path: Path,
    since: datetime | None = None,
) -> list[dict[str, str]]:
    calls: list[dict[str, str]] = []
    for record in read_records(path):
        if not record_is_in_range(record, since):
            continue
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
    """Yield strings without printing or retaining their surrounding content."""
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
    """Map Agent tool-use IDs to transcript IDs found in tool results."""
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


def subagent_transcripts(main_path: Path) -> list[Path]:
    folder = main_path.with_suffix("") / "subagents"
    if not folder.is_dir():
        return []
    return sorted(
        folder.rglob("agent-*.jsonl"),
        key=lambda item: item.stat().st_mtime,
        reverse=True,
    )


def format_models(models: Counter[str]) -> str:
    return ", ".join(
        f"{model} ({count} messages)" for model, count in models.items()
    ) or "none"


def model_matches(models: Counter[str], selector: str) -> bool:
    """Match a full ID or a Claude alias such as sonnet against actual IDs."""
    wanted = selector.lower()
    return any(wanted == model.lower() or wanted in model.lower() for model in models)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify capability-based Claude Code model routing."
    )
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument(
        "--claude-home",
        type=Path,
        default=Path.home() / ".claude",
    )
    parser.add_argument("--main-model", default="claude-fable-5")
    parser.add_argument("--collector-model", default="claude-opus-4-8")
    parser.add_argument("--analyst-model", default="claude-opus-4-8")
    parser.add_argument("--worker-model", default="sonnet")
    parser.add_argument(
        "--since",
        help="Only inspect records at or after this ISO-8601 timestamp.",
    )
    args = parser.parse_args()

    since = parse_timestamp(args.since) if args.since else None
    if args.since and since is None:
        print(f"Invalid --since timestamp: {args.since}", file=sys.stderr)
        return 2

    try:
        main_path = latest_main_transcript(args.claude_home, args.project)
    except FileNotFoundError as error:
        print(error, file=sys.stderr)
        return 1

    main_models = message_models(main_path, since)
    calls = agent_calls(main_path, since)
    paths = subagent_transcripts(main_path)
    subagent_models = [
        (path, models)
        for path in paths
        if (models := message_models(path, since))
    ]
    transcripts_by_id = {
        path.stem.removeprefix("agent-"): (path, models)
        for path, models in subagent_models
    }
    links = agent_result_links(main_path, calls, set(transcripts_by_id))

    print(f"Project: {args.project.resolve()}")
    print(f"Session: {main_path.stem}")
    if since:
        print(f"Since: {since.isoformat()}")
    print(f"Main: {format_models(main_models)}")
    print("Agent calls:")
    if calls:
        for call in calls:
            override = call["model_override"] or "<frontmatter>"
            transcript_id = links.get(call["id"])
            if transcript_id:
                transcript_path, actual_models = transcripts_by_id[transcript_id]
                actual = f"{transcript_path.name}: {format_models(actual_models)}"
            else:
                actual = "unlinked"
            print(
                f"  - {call['type']} | model={override} | actual={actual} | "
                f"{call['description']} | {call['timestamp']}"
            )
    else:
        print("  - none")

    print("Delegated transcripts, including workflows:")
    if subagent_models:
        base = main_path.with_suffix("") / "subagents"
        for path, models in subagent_models:
            print(f"  - {path.relative_to(base)}: {format_models(models)}")
    else:
        print("  - none")

    expected_by_agent = {
        "data-collector": args.collector_model,
        "data-analyst": args.analyst_model,
        "research-worker": args.worker_model,
    }
    routed_context_found = any(
        model_matches(models, selector)
        for _, models in subagent_models
        for selector in expected_by_agent.values()
    )
    mismatches: list[str] = []
    for call in calls:
        selector = expected_by_agent.get(call["type"])
        if selector is None:
            continue
        transcript_id = links.get(call["id"])
        if transcript_id is None:
            mismatches.append(f"{call['type']} call could not be linked to a transcript")
            continue
        _, models = transcripts_by_id[transcript_id]
        if not model_matches(models, selector):
            mismatches.append(
                f"{call['type']} expected {selector}, got {format_models(models)}"
            )

    delegated_main = [
        path
        for path, models in subagent_models
        if model_matches(models, args.main_model)
    ]
    has_main = model_matches(main_models, args.main_model)
    passed = (
        has_main
        and routed_context_found
        and not mismatches
        and not delegated_main
    )

    print()
    if mismatches:
        for mismatch in mismatches:
            print(f"MISMATCH: {mismatch}")
    if delegated_main:
        print("DELEGATED MAIN-MODEL CONTEXTS:")
        for path in delegated_main:
            print(f"  - {path}")
    if not routed_context_found:
        print("NO ROUTED CONTEXT: no configured Opus or Sonnet agent ran in this range.")
    print(
        "PASS: delegated work used configured non-main models without Fable workers."
        if passed
        else "NOT VERIFIED: routing was absent, mismatched, or delegated work used Fable."
    )
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
