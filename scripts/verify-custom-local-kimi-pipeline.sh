#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
. "$script_dir/custom-local-kimi-helpers.sh"

python_bin="$(agentflow_repo_python "$repo_root")"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pipeline_path="$tmpdir/custom-kimi-smoke.yaml"
write_custom_local_kimi_pipeline \
  "$pipeline_path" \
  "custom-kimi-smoke" \
  "Temporary external real-agent smoke test for local Codex plus Claude-on-Kimi."

printf "custom pipeline path: %s\n" "$pipeline_path"

(
  cd "$repo_root"
  "$python_bin" -m agentflow check-local "$pipeline_path" --output summary
)
