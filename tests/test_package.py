from __future__ import annotations

import json
import re
import py_compile
import tempfile
import unittest
from pathlib import Path

from scripts import verify_routing


ROOT = Path(__file__).resolve().parents[1]
AGENT = ROOT / ".claude" / "agents" / "data-collector.md"
SKILL = ROOT / ".claude" / "skills" / "collect-data" / "SKILL.md"
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
    def test_agent_routing_and_limits(self) -> None:
        frontmatter = scalar_frontmatter(AGENT)
        self.assertEqual(frontmatter["name"], "data-collector")
        self.assertEqual(frontmatter["model"], "claude-opus-4-8")
        self.assertEqual(frontmatter["effort"], "low")
        self.assertEqual(frontmatter["permissionMode"], "plan")
        self.assertEqual(frontmatter["maxTurns"], "12")
        text = AGENT.read_text(encoding="utf-8")
        for denied in ("Write", "Edit", "NotebookEdit", "Agent", "Skill"):
            self.assertIn(f"  - {denied}", text)

    def test_evidence_packet_contract(self) -> None:
        text = AGENT.read_text(encoding="utf-8")
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

    def test_skill_is_manual_fork(self) -> None:
        frontmatter = scalar_frontmatter(SKILL)
        self.assertEqual(frontmatter["name"], "collect-data")
        self.assertEqual(frontmatter["disable-model-invocation"], "true")
        self.assertEqual(frontmatter["model"], "claude-opus-4-8")
        self.assertEqual(frontmatter["effort"], "low")
        self.assertEqual(frontmatter["context"], "fork")
        self.assertEqual(frontmatter["agent"], "data-collector")
        self.assertIn("$ARGUMENTS", SKILL.read_text(encoding="utf-8"))

    def test_policy_has_configurable_model_and_serial_default(self) -> None:
        text = POLICY.read_text(encoding="utf-8")
        self.assertIn("{{COLLECTOR_MODEL}}", text)
        self.assertIn("Run one collector at a time", text)
        self.assertIn("Do not silently collect with Fable 5", text)

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
        ):
            self.assertIn(heading, readme)

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


if __name__ == "__main__":
    unittest.main()
