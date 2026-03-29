from __future__ import annotations

from agentflow.remote.lambda_handler import handler


def test_handler_runs_echo_command():
    result = handler(
        {
            "command": ["echo", "hello"],
            "env": {},
            "timeout_seconds": 10,
            "runtime_files": {},
        },
        None,
    )

    assert result["exit_code"] == 0
    assert result["stdout_lines"] == ["hello"]
    assert result["timed_out"] is False


def test_handler_missing_command():
    result = handler({}, None)

    assert result["exit_code"] == 1


def test_handler_timeout():
    result = handler(
        {
            "command": ["sleep", "10"],
            "timeout_seconds": 1,
            "runtime_files": {},
        },
        None,
    )

    assert result["timed_out"] is True
    assert result["exit_code"] == 124


def test_handler_bad_command():
    result = handler(
        {
            "command": ["nonexistent_cmd_xyz"],
            "timeout_seconds": 5,
            "runtime_files": {},
        },
        None,
    )

    assert result["exit_code"] == 127
