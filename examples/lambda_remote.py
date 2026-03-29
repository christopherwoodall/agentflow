from agentflow import DAG, codex, claude

with DAG("lambda-remote-demo", working_dir=".", concurrency=2) as dag:
    scan = codex(
        task_id="scan",
        prompt="List the top-level files and directories in this project. Summarize the repo structure.",
        tools="read_only",
        target={
            "kind": "aws_lambda",
            "function_name": "agentflow-runner",
            "region": "us-east-1",
            "remote_workdir": "/tmp/project",
        },
    )
    review = claude(
        task_id="review",
        prompt=(
            "Review the Lambda scan output and suggest improvements.\n\n"
            "Scan:\n{{ nodes.scan.output }}"
        ),
    )
    scan >> review

print(dag.to_json())
