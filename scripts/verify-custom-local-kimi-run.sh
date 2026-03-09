#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
. "$script_dir/custom-local-kimi-helpers.sh"

python_bin="$(agentflow_repo_python "$repo_root")"

tmpdir="$(mktemp -d)"

pipeline_path="$tmpdir/custom-kimi-run.yaml"
stdout_path="$tmpdir/run.stdout"
stderr_path="$tmpdir/run.stderr"

cleanup() {
  local exit_code=$?
  trap - EXIT
  if [ "$exit_code" -eq 0 ]; then
    rm -rf "$tmpdir"
    return
  fi

  if [ -f "$stderr_path" ]; then
    printf "\nagentflow run stderr:\n" >&2
    sed -n '1,200p' "$stderr_path" >&2
  fi
  if [ -f "$stdout_path" ]; then
    printf "\nagentflow run stdout:\n" >&2
    sed -n '1,200p' "$stdout_path" >&2
  fi
  printf "\nkept tempdir for debugging: %s\n" "$tmpdir" >&2
}

trap cleanup EXIT

write_custom_local_kimi_pipeline \
  "$pipeline_path" \
  "custom-kimi-run" \
  "Temporary external real-agent run test for local Codex plus Claude-on-Kimi."

printf "custom run pipeline path: %s\n" "$pipeline_path"

(
  cd "$repo_root"
  "$python_bin" -m agentflow run "$pipeline_path" --output json-summary --show-preflight >"$stdout_path" 2>"$stderr_path"
)

STDOUT_PATH="$stdout_path" STDERR_PATH="$stderr_path" "$python_bin" - <<'PY'
import json
import os
from pathlib import Path

stdout_path = Path(os.environ["STDOUT_PATH"])
stderr_path = Path(os.environ["STDERR_PATH"])
stdout_text = stdout_path.read_text(encoding="utf-8")
stderr_text = stderr_path.read_text(encoding="utf-8")

payload = json.loads(stdout_text)
if payload.get("status") != "completed":
    raise SystemExit(f"Unexpected run status in stdout JSON: {payload}")

pipeline = payload.get("pipeline") or {}
if pipeline.get("name") != "custom-kimi-run":
    raise SystemExit(f"Unexpected pipeline summary in stdout JSON: {payload}")

nodes = {node.get("id"): node for node in payload.get("nodes", [])}
expected_nodes = {"codex_plan", "claude_review"}
if set(nodes) != expected_nodes:
    raise SystemExit(f"Unexpected node ids in stdout JSON: {sorted(nodes)}")

for node_id, expected_preview in (("codex_plan", "codex ok"), ("claude_review", "claude ok")):
    node = nodes[node_id]
    if node.get("status") != "completed":
        raise SystemExit(f"Node {node_id!r} did not complete: {node}")
    preview = node.get("preview") or ""
    if expected_preview not in preview:
        raise SystemExit(f"Node {node_id!r} preview missing {expected_preview!r}: {node}")

required_stderr_fragments = (
    "Doctor: ok",
    "Pipeline auto preflight: enabled - local Codex/Claude/Kimi nodes use a `kimi` shell bootstrap.",
    "Pipeline auto preflight matches: codex_plan (codex) via `target.bootstrap`, claude_review (claude) via `target.bootstrap`",
)
for fragment in required_stderr_fragments:
    if fragment not in stderr_text:
        raise SystemExit(f"Missing stderr fragment {fragment!r}.\n--- stderr ---\n{stderr_text}")

if "Doctor:" in stdout_text:
    raise SystemExit(f"Preflight summary leaked into stdout.\n--- stdout ---\n{stdout_text}")

print("validated agentflow run json-summary stdout and preflight stderr")
PY
