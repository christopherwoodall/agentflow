# Tuned Agent Evolution — Demo Example

Take one graded run of codex, let an optimizer agent edit codex's tunable
surfaces in response to the failure it sees, rebuild, and ship a measurably
better `codex_tuned` binary. The task is a Terminal-Bench XSS filter,
so the improvement shows up as a verifier score change.

## File layout

```
examples/tune/
  README.md           ← this file
  evolution.py        ← step 1: solve → verify → evolve
  ab_compare.py       ← step 2: tuned → verify_tuned
  verify_filter.py    ← hidden 23-case XSS verifier (from Terminal-Bench)
```

Supporting files outside this directory:

- `agent_tuner/codex_fast.yaml` — tuner profile (skips `cargo test`, lists the
  verified tunable surfaces, carries the aggressive-specialization prompt).
- `agentflow/agents/codex.py::_maybe_prepend_wrapper` — reads
  `<codex-rs>/agentflow_wrapper.md` at prepare-time and concatenates it into
  the user prompt. This is the only surface that reaches the model when codex
  is routed through a gateway proxy.

## Prerequisites

```bash
# 1. agentflow (editable install from this repo)
pip install -e .[dev]

# 2. codex CLI (this example used 0.128.0)
npm install -g @openai/codex
codex login                  # or set OPENAI_API_KEY / configure your provider in ~/.codex/config.toml

# 3. Rust toolchain — evolve auto-clones openai/codex and runs `cargo build`
rustup --version             # if missing: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

## Run

From the repo root:

```bash
agentflow run examples/tune/evolution.py     # ~5–15 min (first build is slow, cache helps later)
agentflow run examples/tune/ab_compare.py    # ~1–2 min
```

## Inspect

```bash
# Verifier reports
cat .agentflow/teach/verifier_report.txt                              # baseline
cat .agentflow/runs/$(ls -t .agentflow/runs | head -1)/artifacts/verify_tuned/output.txt

# What the optimizer changed
VER=$(ls -t .agentflow/tuned_agents/codex_tuned/versions/ | head -1)
cd .agentflow/tuned_agents/codex_tuned/versions/$VER/repo && git add -A && git diff --cached HEAD

# The wrapper text that actually steered the tuned agent
cat .agentflow/tuned_agents/codex_tuned/versions/$VER/repo/codex-rs/agentflow_wrapper.md
```

## Clean re-run

```bash
rm -rf .agentflow/runs .agentflow/tuned_agents .agentflow/teach && mkdir -p .agentflow/teach
```

## Design notes

**Hidden verifier.** `verify_filter.py` has 23 cases adapted verbatim from
Terminal-Bench `filter-js-from-html`. The agent never sees it: it's not in
the task prompt and lives in `examples/tune/`, not in the agent's working
directory. Only the optimizer reads the report it writes, via the
`codex_fast.yaml` evolution prompt.