#!/usr/bin/env bash
set -euo pipefail

bash -lic '
command -v kimi >/dev/null 2>&1
kimi
[ -n "${ANTHROPIC_API_KEY:-}" ]
[ -n "${ANTHROPIC_BASE_URL:-}" ]
printf "ANTHROPIC_BASE_URL=%s\n" "$ANTHROPIC_BASE_URL"
printf "codex: "
codex --version
printf "claude: "
claude --version
' 2> >(
  grep -v \
    -e '^bash: cannot set terminal process group (' \
    -e '^bash: initialize_job_control: no job control in background:' \
    -e '^bash: no job control in this shell$' >&2
)
