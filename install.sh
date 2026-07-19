#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
claude_home="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
collector_model="claude-opus-4-8"
dry_run=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--claude-home PATH] [--collector-model MODEL] [--dry-run]
EOF
}

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
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$collector_model" =~ ^[A-Za-z0-9._:/\-\[\]]+$ ]]; then
  echo "Unsafe collector model value: $collector_model" >&2
  exit 2
fi

agent_source="$repo_root/.claude/agents/data-collector.md"
skill_source="$repo_root/.claude/skills/collect-data/SKILL.md"
policy_source="$repo_root/templates/research-model-routing.md"
agent_target="$claude_home/agents/data-collector.md"
skill_target="$claude_home/skills/collect-data/SKILL.md"
memory_target="$claude_home/CLAUDE.md"

for source in "$agent_source" "$skill_source" "$policy_source"; do
  [[ -f "$source" ]] || { echo "Missing package file: $source" >&2; exit 1; }
done

if [[ $dry_run -eq 1 ]]; then
  echo "[dry-run] install agent -> $agent_target"
  echo "[dry-run] install skill -> $skill_target"
  echo "[dry-run] merge routing policy -> $memory_target"
  echo "[dry-run] collector model: $collector_model"
  exit 0
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_root="$claude_home/backups/optimize-claude-model-research/$timestamp"

sed "s|^model:.*$|model: $collector_model|" "$agent_source" > "$temp_dir/data-collector.md"
sed "s|^model:.*$|model: $collector_model|" "$skill_source" > "$temp_dir/SKILL.md"
sed "s|{{COLLECTOR_MODEL}}|$collector_model|g" "$policy_source" > "$temp_dir/policy.md"

backup_target() {
  local target="$1"
  [[ -f "$target" ]] || return 0
  local relative="${target#"$claude_home"/}"
  local backup="$backup_root/$relative"
  mkdir -p "$(dirname "$backup")"
  cp "$target" "$backup"
}

backup_target "$agent_target"
backup_target "$skill_target"
backup_target "$memory_target"

mkdir -p "$(dirname "$agent_target")" "$(dirname "$skill_target")"
cp "$temp_dir/data-collector.md" "$agent_target"
cp "$temp_dir/SKILL.md" "$skill_target"

begin_marker='<!-- BEGIN optimize-claude-model-research -->'
end_marker='<!-- END optimize-claude-model-research -->'
if [[ -f "$memory_target" ]]; then
  awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin { skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$memory_target" > "$temp_dir/memory-without-router.md"
else
  : > "$temp_dir/memory-without-router.md"
fi

{
  sed -e '${/^$/d;}' "$temp_dir/memory-without-router.md"
  if [[ -s "$temp_dir/memory-without-router.md" ]]; then printf '\n'; fi
  printf '%s\n' "$begin_marker"
  cat "$temp_dir/policy.md"
  printf '%s\n' "$end_marker"
} > "$memory_target"

if [[ -n "${CLAUDE_CODE_SUBAGENT_MODEL:-}" && "${CLAUDE_CODE_SUBAGENT_MODEL}" != "inherit" ]]; then
  echo "Warning: CLAUDE_CODE_SUBAGENT_MODEL=${CLAUDE_CODE_SUBAGENT_MODEL} overrides the configured collector model." >&2
fi

echo "Installed Claude Research Router in $claude_home"
echo "Collector model: $collector_model"
echo "Restart Claude Code, then run /doctor, /skills, and /agents."
