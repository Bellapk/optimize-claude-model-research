import py_compile
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def frontmatter(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not match:
        raise AssertionError(f"Missing frontmatter: {path}")
    return match.group(1)


class PackageTests(unittest.TestCase):
    def test_agent_configuration(self):
        path = ROOT / ".claude" / "agents" / "data-collector.md"
        meta = frontmatter(path)
        for expected in (
            "name: data-collector",
            "model: claude-opus-4-8",
            "effort: low",
            "permissionMode: plan",
            "maxTurns: 12",
            "  - Write",
            "  - Edit",
            "  - Agent",
            "  - Skill",
        ):
            self.assertIn(expected, meta)

    def test_skill_configuration(self):
        path = ROOT / ".claude" / "skills" / "collect-data" / "SKILL.md"
        meta = frontmatter(path)
        for expected in (
            "name: collect-data",
            "disable-model-invocation: true",
            "model: claude-opus-4-8",
            "effort: low",
            "context: fork",
            "agent: data-collector",
        ):
            self.assertIn(expected, meta)
        self.assertIn("$ARGUMENTS", path.read_text(encoding="utf-8"))

    def test_evidence_packet_contract(self):
        text = (ROOT / ".claude" / "agents" / "data-collector.md").read_text(
            encoding="utf-8"
        )
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

    def test_policy_is_installable(self):
        text = (ROOT / "templates" / "research-model-routing.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("{{COLLECTOR_MODEL}}", text)
        self.assertIn("Run one collector at a time", text)
        self.assertIn("Do not silently collect with the main reasoning model", text)

    def test_verifier_compiles(self):
        py_compile.compile(
            str(ROOT / "scripts" / "verify_routing.py"), doraise=True
        )

    def test_readme_has_quickstart_and_limits(self):
        text = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("## Quick start", text)
        self.assertIn("## Verify the model split", text)
        self.assertIn("## What this does not promise", text)


if __name__ == "__main__":
    unittest.main()
