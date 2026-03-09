#!/usr/bin/env bash

agentflow_repo_python() {
  local repo_root="$1"
  local python_bin="${AGENTFLOW_PYTHON:-}"

  if [ -n "$python_bin" ]; then
    printf '%s\n' "$python_bin"
    return
  fi

  if [ -x "$repo_root/.venv/bin/python" ]; then
    printf '%s\n' "$repo_root/.venv/bin/python"
    return
  fi

  printf '%s\n' "python3"
}

write_custom_local_kimi_pipeline() {
  local pipeline_path="$1"
  local pipeline_name="$2"
  local pipeline_description="$3"

  cat >"$pipeline_path" <<YAML
name: $pipeline_name
description: $pipeline_description
working_dir: .
concurrency: 2
local_target_defaults:
  bootstrap: kimi
nodes:
  - id: codex_plan
    agent: codex
    env:
      OPENAI_BASE_URL: ""
    prompt: |
      Reply with exactly: codex ok
    timeout_seconds: 180
    success_criteria:
      - kind: output_contains
        value: codex ok

  - id: claude_review
    agent: claude
    provider: kimi
    prompt: |
      Reply with exactly: claude ok
    timeout_seconds: 180
    success_criteria:
      - kind: output_contains
        value: claude ok
YAML
}
