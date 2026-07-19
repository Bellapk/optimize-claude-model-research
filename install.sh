#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
claude_home="${CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-${HOME}/.claude}}"
collector_model="claude-opus-4-8"
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude-home)
      claude_home="$2"
      shift 2
      ;;
    --collector-model)
      collector_model="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      echo "Usage: ./install.sh [--claude-home PATH] [--collector-model MODEL] [--dry-run]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ ! "$collector_model" =~ ^[[:alnum:]_.:/-]+(\[[[:alnum:]]+\])?$ ]]; then
  echo "Collector model contains unsupported characters: $collector_model" >&2
  exit 2
fi

agent_source="$repo_root/.claude/agents/data-collector.md"
skill_source="$repo_root/.claude/skills/collect-data/SKILL.md"
policy_source="$repo_root/templates/research-model-routing.md"
agent_target="$claude_home/agents/data-collector.md"
skill_target="$claude_home/skills/collect-data/SKILL.md"
policy_target="$claude_home/CLAUDE.md"

for source in "$agent_source" "$skill_source" "$policy_source"; do
  [[ -f "$source" ]] || { echo "Missing package file: $source" >&2; exit 1; }
done

if [[ "$dry_run" -eq 1 ]]; then
  echo "[dry-run] install $agent_target"
  echo "[dry-run] install $skill_target"
  echo "[dry-run] merge policy into $policy_target"
  exit 0
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_root="$claude_home/backups/optimize-claude-model-research/$timestamp"

sed "s|^model:.*|model: $collector_model|" "$agent_source" > "$temp_dir/data-collector.md"
sed "s|^model:.*|model: $collector_model|" "$skill_source" > "$temp_dir/SKILL.md"
sed "s|{{COLLECTOR_MODEL}}|$collector_model|g" "$policy_source" > "$temp_dir/policy.md"

begin_marker="<!-- BEGIN optimize-claude-model-research -->"
end_marker="<!-- END optimize-claude-model-research -->"
if [[ -f "$policy_target" ]]; then
  awk -v begin="$begin_marker" -v end="$end_marker" '
    {
      comparable=$0
      sub(/\r$/, "", comparable)
    }
    comparable == begin { skipping=1; next }
    comparable == end { skipping=0; next }
    !skipping && $0 ~ /^[[:space:]]*$/ { trailing=trailing $0 ORS; next }
    !skipping { printf "%s", trailing; trailing=""; print }
  ' "$policy_target" > "$temp_dir/policy-base.md"
else
  : > "$temp_dir/policy-base.md"
fi

{
  cat "$temp_dir/policy-base.md"
  if [[ -s "$temp_dir/policy-base.md" ]]; then printf "\n"; fi
  printf '%s\n' "$begin_marker"
  cat "$temp_dir/policy.md"
  printf '%s\n' "$end_marker"
} > "$temp_dir/CLAUDE.md"

install_file() {
  local source="$1"
  local target="$2"
  if [[ -f "$target" ]] && ! cmp -s "$source" "$target"; then
    local relative="${target#"$claude_home"/}"
    local backup_target="$backup_root/$relative"
    mkdir -p "$(dirname -- "$backup_target")"
    cp "$target" "$backup_target"
    echo "Backed up $target"
  fi
  mkdir -p "$(dirname -- "$target")"
  cp "$source" "$target"
  echo "Installed $target"
}

install_file "$temp_dir/data-collector.md" "$agent_target"
install_file "$temp_dir/SKILL.md" "$skill_target"
install_file "$temp_dir/CLAUDE.md" "$policy_target"

if [[ -n "${CLAUDE_CODE_SUBAGENT_MODEL:-}" && "${CLAUDE_CODE_SUBAGENT_MODEL}" != "inherit" ]]; then
  echo "WARNING: CLAUDE_CODE_SUBAGENT_MODEL=${CLAUDE_CODE_SUBAGENT_MODEL} overrides the collector model." >&2
fi

echo
echo "Claude Research Router is installed with collector model: $collector_model"
echo "Restart Claude Code, then run /doctor, /memory, /skills, and /agents."
echo "Smoke test: /collect-data Collect two primary sources for a narrow research question."
