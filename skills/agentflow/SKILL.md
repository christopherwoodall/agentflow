# AgentFlow Skill

AgentFlow orchestrates codex, claude, and kimi agents in dependency-aware graphs. Agents run locally, via SSH, on EC2, or on ECS Fargate.

## Core API (2 imports for simple, 4 for fanout)

```python
from agentflow import Graph, codex, claude, kimi, fanout, merge
```

## Basic Graph

```python
with Graph("my-pipeline", concurrency=3) as g:
    plan = codex(task_id="plan", prompt="Plan the work.", tools="read_only")
    impl = claude(task_id="impl", prompt="Implement:\n{{ nodes.plan.output }}", tools="read_write")
    review = codex(task_id="review", prompt="Review:\n{{ nodes.impl.output }}")

    plan >> impl >> review  # dependency chain

print(g.to_json())  # outputs JSON, pipe to `agentflow run`
```

Run: `python pipeline.py | agentflow run -` or `agentflow run pipeline.py`

## Template Variables

In prompts, use Jinja2:
- `{{ nodes.<task_id>.output }}` -- output of a completed node
- `{{ nodes.<task_id>.status }}` -- "completed", "failed", etc.
- `{{ fanouts.<group>.nodes }}` -- all members of a fanout group
- `{{ item.number }}`, `{{ item.suffix }}` -- fanout member fields

## Fanout (parallel shards)

`fanout(node, source)` wraps a node to run as many parallel copies:

```python
# Count: 128 identical shards
shards = fanout(codex(task_id="shard", prompt="Shard {{ item.number }}/{{ item.count }}"), 128)

# Values: one per item
reviews = fanout(codex(task_id="review", prompt="Review {{ item.repo }}"),
    [{"repo": "api"}, {"repo": "billing"}, {"repo": "auth"}])

# Matrix: cartesian product
fuzz = fanout(codex(task_id="fuzz", prompt="{{ item.target }} {{ item.sanitizer }}"),
    {"target": [{"name": "libpng"}, {"name": "sqlite"}],
     "check": [{"sanitizer": "asan"}, {"sanitizer": "ubsan"}]})
```

### item fields (fanout)

| Field | Example |
|---|---|
| `item.index` | 0, 1, 2 |
| `item.number` | 1, 2, 3 |
| `item.count` | total |
| `item.suffix` | "000", "001" |
| `item.node_id` | "shard_001" |
| `item.<key>` | lifted from value dicts |

### derive (computed fields)

```python
fanout(node, 128, derive={"workspace": "agents/{{ item.suffix }}"})
# item.workspace = "agents/000", "agents/001", ...
```

## Merge (reduce fanout results)

`merge(node, source_node, by=[...] | size=N)`:

```python
# Batch: one reducer per 16 shards
batch = merge(codex(task_id="batch", prompt="Reduce {{ item.start_number }}-{{ item.end_number }}"),
    shards, size=16)

# Group by field
family = merge(codex(task_id="family", prompt="Reduce {{ item.target }}"),
    fuzz, by=["target"])
```

### item fields (merge)

All fanout fields plus: `item.source_group`, `item.member_ids`, `item.members`, `item.size`.

At runtime: `item.scope.nodes`, `item.scope.outputs`, `item.scope.summary.completed`, `item.scope.with_output`, `item.scope.without_output`.

## Cycles (iterative loops)

```python
with Graph("iterative", max_iterations=5) as g:
    write = codex(task_id="write", prompt="Write code.\n{% if nodes.review.output %}Fix: {{ nodes.review.output }}{% endif %}")
    review = claude(task_id="review", prompt="Review:\n{{ nodes.write.output }}",
        success_criteria=[{"kind": "output_contains", "value": "LGTM"}])

    write >> review
    review.on_failure >> write  # loop back until LGTM or max_iterations
```

## Execution Targets

### Local (default)
```python
codex(task_id="t", prompt="...", tools="read_write")
```

### SSH
```python
codex(task_id="t", prompt="...", target={"kind": "ssh", "host": "server", "username": "deploy"})
```

### EC2 (auto-discovers AMI, key pair, VPC)
```python
codex(task_id="t", prompt="...", target={
    "kind": "ec2",
    "region": "us-east-1",         # only required field
    "instance_type": "t3.medium",  # optional
    "terminate": True,             # auto-terminate after (default)
    "snapshot": False,             # create AMI before terminate
    "shared": "dev-box",          # reuse instance across nodes
})
```

### ECS Fargate (auto-discovers VPC, builds image)
```python
codex(task_id="t", prompt="...", target={
    "kind": "ecs",
    "region": "us-east-1",         # only required field
    "image": "ubuntu:24.04",       # optional base image
    "install_agents": ["codex"],   # auto-install in image
    "cpu": "2048",                 # optional
    "memory": "4096",              # optional
})
```

### Shared instances
Nodes with the same `shared` ID reuse one instance:
```python
plan = codex(task_id="plan", prompt="...", target={"kind": "ec2", "shared": "box"})
impl = codex(task_id="impl", prompt="...", target={"kind": "ec2", "shared": "box"})
plan >> impl  # same EC2 instance, files persist between nodes
```

## Scratchboard (shared memory)

```python
with Graph("campaign", scratchboard=True) as g:
    shards = fanout(codex(task_id="fuzz", prompt="..."), 128)
```

All agents get a `scratchboard.md` file. They can read it for context from other agents and append critical findings. The orchestrator merges writes from remote nodes.

## Graph Options

```python
Graph(
    "name",
    concurrency=4,          # max parallel nodes
    fail_fast=False,         # skip downstream on failure
    max_iterations=10,       # cycle limit
    scratchboard=False,      # shared memory file
    node_defaults={...},     # applied to all nodes
    agent_defaults={...},    # per-agent defaults
)
```

## Node Options

```python
codex(
    task_id="name",          # unique ID
    prompt="...",            # Jinja2 template
    tools="read_only",      # or "read_write"
    model="gpt-5-codex",    # optional model override
    timeout_seconds=300,     # optional timeout
    retries=1,              # optional retry count
    success_criteria=[{"kind": "output_contains", "value": "PASS"}],
    target={...},           # execution target
    env={"KEY": "val"},     # environment variables
    schedule={"every_seconds": 600, "until_fanout_settles_from": "shards"},  # periodic
)
```

## CLI

```bash
agentflow run pipeline.py           # run a pipeline
agentflow run pipeline.py --output summary
agentflow validate pipeline.py      # check without running
agentflow inspect pipeline.py       # show expanded graph
agentflow templates                  # list bundled templates
agentflow init > pipeline.py        # scaffold a starter pipeline
agentflow serve                      # web UI
```
