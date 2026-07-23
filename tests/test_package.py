from __future__ import annotations

import json
import re
import py_compile
import tempfile
import unittest
from collections import Counter
from pathlib import Path

from scripts import verify_routing


ROOT = Path(__file__).resolve().parents[1]
COLLECTOR_AGENT = ROOT / ".claude" / "agents" / "data-collector.md"
ANALYST_AGENT = ROOT / ".claude" / "agents" / "data-analyst.md"
WORKER_AGENT = ROOT / ".claude" / "agents" / "research-worker.md"
COLLECT_SKILL = ROOT / ".claude" / "skills" / "collect-data" / "SKILL.md"
ANALYZE_SKILL = ROOT / ".claude" / "skills" / "analyze-data" / "SKILL.md"
EXECUTE_SKILL = ROOT / ".claude" / "skills" / "execute-research" / "SKILL.md"
ROUTE_SKILL = ROOT / ".claude" / "skills" / "route-research" / "SKILL.md"
PLAN_SKILL = ROOT / ".claude" / "skills" / "execute-research-plan" / "SKILL.md"
POLICY = ROOT / "templates" / "research-model-routing.md"


def scalar_frontmatter(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not match:
        raise AssertionError(f"Missing frontmatter: {path}")
    values: dict[str, str] = {}
    for line in match.group(1).splitlines():
        item = re.match(r"^([A-Za-z][A-Za-z0-9_-]*):\s*(.*?)\s*$", line)
        if item:
            values[item.group(1)] = item.group(2).strip('"')
    return values


class PackageTests(unittest.TestCase):
    def test_collector_routing_and_limits(self) -> None:
        frontmatter = scalar_frontmatter(COLLECTOR_AGENT)
        self.assertEqual(frontmatter["name"], "data-collector")
        self.assertEqual(frontmatter["model"], "claude-opus-4-8")
        self.assertEqual(frontmatter["effort"], "low")
        self.assertEqual(frontmatter["permissionMode"], "plan")
        self.assertEqual(frontmatter["maxTurns"], "12")
        text = COLLECTOR_AGENT.read_text(encoding="utf-8")
        for denied in ("Write", "Edit", "NotebookEdit", "Agent", "Skill"):
            self.assertIn(f"  - {denied}", text)

    def test_evidence_packet_contract(self) -> None:
        text = COLLECTOR_AGENT.read_text(encoding="utf-8")
        for heading in (
            "## Collection status",
            "## Requirement and scope",
            "## Sources examined",
            "## Evidence collected",
            "## Conflicts and limitations",
            "## Missing evidence",
            "## Recommended next collection step",
        ):
            self.assertIn(heading, text)

    def test_collect_skill_is_automatic_opus_fork(self) -> None:
        frontmatter = scalar_frontmatter(COLLECT_SKILL)
        self.assertEqual(frontmatter["name"], "collect-data")
        self.assertNotIn("disable-model-invocation", frontmatter)
        self.assertEqual(frontmatter["model"], "claude-opus-4-8")
        self.assertEqual(frontmatter["effort"], "low")
        self.assertEqual(frontmatter["context"], "fork")
        self.assertEqual(frontmatter["agent"], "data-collector")
        self.assertIn("$ARGUMENTS", COLLECT_SKILL.read_text(encoding="utf-8"))

    def test_analyst_uses_opus_for_tables(self) -> None:
        frontmatter = scalar_frontmatter(ANALYST_AGENT)
        self.assertEqual(frontmatter["name"], "data-analyst")
        self.assertEqual(frontmatter["model"], "claude-opus-4-8")
        self.assertEqual(frontmatter["effort"], "medium")
        self.assertEqual(frontmatter["permissionMode"], "acceptEdits")
        self.assertEqual(frontmatter["maxTurns"], "16")
        text = ANALYST_AGENT.read_text(encoding="utf-8")
        self.assertIn("canonical machine-readable tables", text)
        for denied in ("Agent", "Skill", "WebSearch", "WebFetch"):
            self.assertIn(f"  - {denied}", text)

        skill = scalar_frontmatter(ANALYZE_SKILL)
        self.assertEqual(skill["model"], "claude-opus-4-8")
        self.assertEqual(skill["effort"], "medium")
        self.assertEqual(skill["context"], "fork")
        self.assertEqual(skill["agent"], "data-analyst")

    def test_worker_uses_latest_sonnet_alias(self) -> None:
        frontmatter = scalar_frontmatter(WORKER_AGENT)
        self.assertEqual(frontmatter["name"], "research-worker")
        self.assertEqual(frontmatter["model"], "sonnet")
        self.assertEqual(frontmatter["effort"], "medium")
        self.assertEqual(frontmatter["permissionMode"], "acceptEdits")
        self.assertEqual(frontmatter["maxTurns"], "20")
        text = WORKER_AGENT.read_text(encoding="utf-8")
        for denied in ("Agent", "WebSearch", "WebFetch"):
            self.assertIn(f"  - {denied}", text)

        skill = scalar_frontmatter(EXECUTE_SKILL)
        self.assertEqual(skill["model"], "sonnet")
        self.assertEqual(skill["effort"], "medium")
        self.assertEqual(skill["context"], "fork")
        self.assertEqual(skill["agent"], "research-worker")

    def test_router_and_plan_executor_define_serial_model_map(self) -> None:
        route = scalar_frontmatter(ROUTE_SKILL)
        self.assertNotIn("disable-model-invocation", route)
        self.assertEqual(route["allowed-tools"], "Agent")
        route_text = ROUTE_SKILL.read_text(encoding="utf-8")
        for agent in ("data-collector", "data-analyst", "research-worker"):
            self.assertIn(f"`{agent}`", route_text)
        self.assertIn("Run only one subagent at a time", route_text)

        plan = scalar_frontmatter(PLAN_SKILL)
        self.assertEqual(plan["disable-model-invocation"], "true")
        self.assertEqual(plan["allowed-tools"], "Agent")
        plan_text = PLAN_SKILL.read_text(encoding="utf-8")
        for task_class in ("JUDGMENT", "COLLECTION", "ANALYSIS", "EXECUTION"):
            self.assertIn(f"`{task_class}`", plan_text)

    def test_policy_has_configurable_model_and_serial_default(self) -> None:
        text = POLICY.read_text(encoding="utf-8")
        self.assertIn("{{COLLECTOR_MODEL}}", text)
        self.assertIn("{{ANALYST_MODEL}}", text)
        self.assertIn("{{WORKER_MODEL}}", text)
        self.assertIn("Run only one subagent at a time", text)
        self.assertIn("Do not use Workflow, Explore, Plan, general-purpose", text)
        self.assertIn("Never fall back to Fable 5", text)

    def test_readme_and_installers_exist(self) -> None:
        for path in (
            ROOT / "README.md",
            ROOT / "install.ps1",
            ROOT / "install.sh",
            ROOT / "scripts" / "verify_routing.py",
        ):
            self.assertTrue(path.is_file(), path)

        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        for heading in (
            "## Quick start",
            "## Verify the models that actually ran",
            "## Safety and usage controls",
            "## Author",
        ):
            self.assertIn(heading, readme)
        self.assertIn("Kun Peng, Ph.D.", readme)
        self.assertIn("https://www.linkedin.com/in/peng-kun/", readme)

        powershell_installer = (ROOT / "install.ps1").read_text(encoding="utf-8")
        shell_installer = (ROOT / "install.sh").read_text(encoding="utf-8")
        for marker in ("AnalystModel", "WorkerModel", "execute-research-plan"):
            self.assertIn(marker, powershell_installer)
        for marker in ("analyst_model", "worker_model", "execute-research-plan"):
            self.assertIn(marker, shell_installer)

    def test_verifier_compiles(self) -> None:
        py_compile.compile(
            str(ROOT / "scripts" / "verify_routing.py"),
            doraise=True,
        )

    def test_verifier_links_collector_call_to_its_transcript(self) -> None:
        transcript_id = "a227e52ab33ab839e"
        records = [
            {
                "message": {
                    "content": [
                        {
                            "type": "tool_use",
                            "name": "Agent",
                            "id": "toolu_test",
                            "input": {
                                "subagent_type": "data-collector",
                                "description": "Collect evidence",
                            },
                        }
                    ]
                }
            },
            {
                "message": {
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "toolu_test",
                            "content": [
                                {
                                    "type": "text",
                                    "text": f"Agent completed with ID {transcript_id}",
                                }
                            ],
                        }
                    ]
                }
            },
        ]
        with tempfile.TemporaryDirectory() as temporary_directory:
            transcript = Path(temporary_directory) / "main.jsonl"
            transcript.write_text(
                "".join(json.dumps(record) + "\n" for record in records),
                encoding="utf-8",
            )
            calls = verify_routing.agent_calls(transcript)
            links = verify_routing.agent_result_links(
                transcript,
                calls,
                {transcript_id},
            )

        self.assertEqual(links, {"toolu_test": transcript_id})

    def test_verifier_matches_alias_and_finds_workflow_agents(self) -> None:
        self.assertTrue(
            verify_routing.model_matches(Counter({"claude-sonnet-5": 2}), "sonnet")
        )
        self.assertFalse(
            verify_routing.model_matches(Counter({"claude-fable-5": 2}), "sonnet")
        )

        with tempfile.TemporaryDirectory() as temporary_directory:
            main = Path(temporary_directory) / "session.jsonl"
            main.write_text("", encoding="utf-8")
            workflow_agent = (
                main.with_suffix("")
                / "subagents"
                / "workflows"
                / "wf-test"
                / "agent-test.jsonl"
            )
            workflow_agent.parent.mkdir(parents=True)
            workflow_agent.write_text("", encoding="utf-8")
            discovered = verify_routing.subagent_transcripts(main)

        self.assertEqual(discovered, [workflow_agent])


if __name__ == "__main__":
    unittest.main()
