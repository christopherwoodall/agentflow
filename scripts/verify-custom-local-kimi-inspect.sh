#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
. "$script_dir/custom-local-kimi-helpers.sh"

python_bin="$(agentflow_repo_python "$repo_root")"

tmpdir="$(mktemp -d)"
inspect_path="$tmpdir/custom-kimi-inspect.yaml"
stdout_path="$tmpdir/inspect.stdout"

cleanup() {
  local exit_code=$?
  trap - EXIT
  if [ "$exit_code" -eq 0 ]; then
    rm -rf "$tmpdir"
    return
  fi

  if [ -f "$stdout_path" ]; then
    printf "\nagentflow inspect stdout:\n" >&2
    sed -n '1,200p' "$stdout_path" >&2
  fi
  printf "\nkept tempdir for debugging: %s\n" "$tmpdir" >&2
}

trap cleanup EXIT

write_custom_local_kimi_pipeline \
  "$inspect_path" \
  "custom-kimi-inspect" \
  "Temporary external inspect test for local Codex plus Claude-on-Kimi."

printf "custom inspect pipeline path: %s\n" "$inspect_path"

(
  cd "$repo_root"
  "$python_bin" -m agentflow inspect "$inspect_path" --output summary >"$stdout_path"
)

PIPELINE_DIR="$tmpdir" STDOUT_PATH="$stdout_path" "$python_bin" - <<'PY'
import os
from pathlib import Path

pipeline_dir = Path(os.environ["PIPELINE_DIR"]).resolve()
stdout_path = Path(os.environ["STDOUT_PATH"])
stdout_text = stdout_path.read_text(encoding="utf-8")

required_fragments = (
    "Pipeline: custom-kimi-inspect",
    f"Working dir: {pipeline_dir}",
    "Auto preflight: enabled - local Codex/Claude/Kimi nodes use a `kimi` shell bootstrap.",
    "Auto preflight matches: codex_plan (codex) via `target.bootstrap`, claude_review (claude) via `target.bootstrap`",
    "- codex_plan [codex/local]",
    "- claude_review [claude/local]",
    "Provider: kimi, key=ANTHROPIC_API_KEY, url=https://api.kimi.com/coding/",
    "Prepared: codex exec",
    "Prepared: claude -p",
    "Launch: bash -l -i -c 'command -v kimi >/dev/null 2>&1 && kimi && eval \"$AGENTFLOW_TARGET_COMMAND\"'",
)

for fragment in required_fragments:
    if fragment not in stdout_text:
        raise SystemExit(f"Missing inspect fragment {fragment!r}.\n--- stdout ---\n{stdout_text}")

cwd_fragment = f"Cwd: {pipeline_dir}"
if stdout_text.count(cwd_fragment) != 2:
    raise SystemExit(
        f"Expected both local nodes to resolve cwd to {pipeline_dir!s}.\n--- stdout ---\n{stdout_text}"
    )

print("validated agentflow inspect summary for external custom pipeline")
PY
