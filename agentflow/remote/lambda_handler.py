from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path


def _write_runtime_files(runtime_dir: Path, runtime_files: dict[str, str]) -> None:
    for relative_path, content in runtime_files.items():
        target = runtime_dir / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")


def _coerce_text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def _response(
    *,
    exit_code: int,
    stdout: str | bytes | None = "",
    stderr: str | bytes | None = "",
    timed_out: bool = False,
    cancelled: bool = False,
) -> dict[str, object]:
    return {
        "exit_code": exit_code,
        "stdout_lines": _coerce_text(stdout).splitlines(),
        "stderr_lines": _coerce_text(stderr).splitlines(),
        "timed_out": timed_out,
        "cancelled": cancelled,
    }


def handler(event, context):
    runtime_root = Path(tempfile.mkdtemp(prefix="agentflow-"))
    try:
        event = event or {}
        _write_runtime_files(runtime_root, event.get("runtime_files", {}))

        command = event.get("command")
        if not command:
            return _response(
                exit_code=1,
                stderr="Missing required 'command' in event.",
            )

        env = os.environ.copy()
        env.update(event.get("env", {}))
        cwd = event.get("cwd") or str(runtime_root)
        stdin = event.get("stdin")
        timeout_seconds = int(event.get("timeout_seconds", 1800))

        try:
            completed = subprocess.run(
                command,
                cwd=cwd,
                env=env,
                input=stdin,
                text=True,
                capture_output=True,
                timeout=timeout_seconds,
                check=False,
            )
            return _response(
                exit_code=completed.returncode,
                stdout=completed.stdout,
                stderr=completed.stderr,
            )
        except subprocess.TimeoutExpired as exc:
            return _response(
                exit_code=124,
                stdout=exc.stdout,
                stderr=exc.stderr,
                timed_out=True,
            )
        except FileNotFoundError as exc:
            return _response(exit_code=127, stderr=str(exc))
        except KeyboardInterrupt:
            return _response(
                exit_code=130,
                stderr="Execution cancelled.",
                cancelled=True,
            )
    finally:
        shutil.rmtree(runtime_root, ignore_errors=True)
