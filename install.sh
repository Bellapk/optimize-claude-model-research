#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
claude_home="${CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-${HOME}/.claude}}"
collector_model="claude-opus-4-8"
analyst_model="claude-opus-4-8"
worker_model="sonnet"
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
    --analyst-model)
      analyst_model="$2"
      shift 2
      ;;
    --worker-model)
      worker_model="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      echo "Usage: ./install.sh [--claude-home PATH] [--collector-model MODEL] [--analyst-model MODEL] [--worker-model MODEL] [--dry-run]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

for model_setting in "$collector_model" "$analyst_model" "$worker_model"; do
  if [[ ! "$model_setting" =~ ^[[:alnum:]_.:/-]+(\[[[:alnum:]]+\])?$ ]]; then
    echo "Model contains unsupported characters: $model_setting" >&2
    exit 2
  fi
done

collector_agent_source="$repo_root/.claude/agents/data-collector.md"
analyst_agent_source="$repo_root/.claude/agents/data-analyst.md"
worker_agent_source="$repo_root/.claude/agents/research-worker.md"
collect_skill_source="$repo_root/.claude/skills/collect-data/SKILL.md"
analyze_skill_source="$repo_root/.claude/skills/analyze-data/SKILL.md"
execute_skill_source="$repo_root/.claude/skills/execute-research/SKILL.md"
route_skill_source="$repo_root/.claude/skills/route-research/SKILL.md"
plan_skill_source="$repo_root/.claude/skills/execute-research-plan/SKILL.md"
policy_source="$repo_root/templates/research-model-routing.md"
collector_agent_target="$claude_home/agents/data-collector.md"
analyst_agent_target="$claude_home/agents/data-analyst.md"
worker_agent_target="$claude_home/agents/research-worker.md"
collect_skill_target="$claude_home/skills/collect-data/SKILL.md"
analyze_skill_target="$claude_home/skills/analyze-data/SKILL.md"
execute_skill_target="$claude_home/skills/execute-research/SKILL.md"
route_skill_target="$claude_home/skills/route-research/SKILL.md"
plan_skill_target="$claude_home/skills/execute-research-plan/SKILL.md"
policy_target="$claude_home/CLAUDE.md"

for source in \
  "$collector_agent_source" "$analyst_agent_source" "$worker_agent_source" \
  "$collect_skill_source" "$analyze_skill_source" "$execute_skill_source" \
  "$route_skill_source" "$plan_skill_source" "$policy_source"; do
  [[ -f "$source" ]] || { echo "Missing package file: $source" >&2; exit 1; }
done

if [[ "$dry_run" -eq 1 ]]; then
  echo "[dry-run] install $collector_agent_target"
  echo "[dry-run] install $analyst_agent_target"
  echo "[dry-run] install $worker_agent_target"
  echo "[dry-run] install $collect_skill_target"
  echo "[dry-run] install $analyze_skill_target"
  echo "[dry-run] install $execute_skill_target"
  echo "[dry-run] install $route_skill_target"
  echo "[dry-run] install $plan_skill_target"
  echo "[dry-run] merge policy into $policy_target"
  exit 0
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_root="$claude_home/backups/optimize-claude-model-research/$timestamp"

sed "s|^model:.*|model: $collector_model|" "$collector_agent_source" > "$temp_dir/data-collector.md"
sed "s|^model:.*|model: $analyst_model|" "$analyst_agent_source" > "$temp_dir/data-analyst.md"
sed "s|^model:.*|model: $worker_model|" "$worker_agent_source" > "$temp_dir/research-worker.md"
sed "s|^model:.*|model: $collector_model|" "$collect_skill_source" > "$temp_dir/collect-data-SKILL.md"
sed "s|^model:.*|model: $analyst_model|" "$analyze_skill_source" > "$temp_dir/analyze-data-SKILL.md"
sed "s|^model:.*|model: $worker_model|" "$execute_skill_source" > "$temp_dir/execute-research-SKILL.md"
cp "$route_skill_source" "$temp_dir/route-research-SKILL.md"
cp "$plan_skill_source" "$temp_dir/execute-research-plan-SKILL.md"
sed \
  -e "s|{{COLLECTOR_MODEL}}|$collector_model|g" \
  -e "s|{{ANALYST_MODEL}}|$analyst_model|g" \
  -e "s|{{WORKER_MODEL}}|$worker_model|g" \
  "$policy_source" > "$temp_dir/policy.md"

begin_marker="<!-- BEGIN optimize-claude-model-research -->"
end_marker="<!-- END optimize-claude-model-research -->"
if [[ -f "$policy_target" ]]; then
  legacy_heading_count="$(grep -c '^# ' "$policy_target" || true)"
  if ! grep -Fq "$begin_marker" "$policy_target" \
    && grep -Fq 'Use the main Fable 5 context only for work that materially requires high-level judgment:' "$policy_target" \
    && [[ "$legacy_heading_count" -eq 1 ]]; then
    : > "$temp_dir/policy-base.md"
    echo "Migrating legacy unmarked router-only CLAUDE.md"
  else
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
  fi
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

install_file "$temp_dir/data-collector.md" "$collector_agent_target"
install_file "$temp_dir/data-analyst.md" "$analyst_agent_target"
install_file "$temp_dir/research-worker.md" "$worker_agent_target"
install_file "$temp_dir/collect-data-SKILL.md" "$collect_skill_target"
install_file "$temp_dir/analyze-data-SKILL.md" "$analyze_skill_target"
install_file "$temp_dir/execute-research-SKILL.md" "$execute_skill_target"
install_file "$temp_dir/route-research-SKILL.md" "$route_skill_target"
install_file "$temp_dir/execute-research-plan-SKILL.md" "$plan_skill_target"
install_file "$temp_dir/CLAUDE.md" "$policy_target"

if [[ -n "${CLAUDE_CODE_SUBAGENT_MODEL:-}" && "${CLAUDE_CODE_SUBAGENT_MODEL}" != "inherit" ]]; then
  echo "WARNING: CLAUDE_CODE_SUBAGENT_MODEL=${CLAUDE_CODE_SUBAGENT_MODEL} overrides all configured agent models." >&2
fi

echo
echo "Claude Research Router is installed."
echo "  Collector: $collector_model"
echo "  Data analyst: $analyst_model"
echo "  Research worker: $worker_model"
echo "Restart Claude Code, then run /doctor, /memory, /skills, and /agents."
echo "Plan workflow: create and approve a plan in Plan mode, then run /execute-research-plan <plan>."
echo "Smoke tests: /collect-data, /analyze-data, and /execute-research."
