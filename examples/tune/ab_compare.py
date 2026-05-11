"""Step 2 of the Tuned Agent Evolution teaching example.

See ``examples/tune/README.md`` for the full walkthrough. Run
``examples/tune/evolution.py`` first so that ``codex_tuned`` is registered.

Baseline reference comes for free from the evolve run: its ``solve`` node
already ran ``codex`` on the same prompt and ``verify`` already graded the
result. Re-running baseline here just burns compute, so this pipeline only
runs the evolved agent.

After this completes, look at:

- baseline reference: ``.agentflow/runs/<evolve_run>/artifacts/verify/output.txt``
- tuned trace:        ``.agentflow/runs/<this_run>/artifacts/tuned/trace.jsonl``
- tuned score:        ``.agentflow/runs/<this_run>/artifacts/verify_tuned/output.txt``
- optimizer diff:     ``cd .agentflow/tuned_agents/codex_tuned/versions/<v>/repo && git diff``

Note: ``codex_tuned`` only resolves on local targets.
"""

from pathlib import Path

from agentflow import Graph, agent, python_node


REPO_ROOT = str(Path(__file__).resolve().parents[2])
VERIFIER_SCRIPT = str(Path(__file__).resolve().parent / "verify_filter.py")
# Same pin as in evolution.py — must match for a fair A/B.
AGENT_MODEL = "gpt-5.3-codex"
VERIFIER_TEMPLATE = """\
import subprocess, sys
from pathlib import Path

verifier = Path(r'{verifier_script}')
root = Path(r'{repo_root}')
candidate = root / '.agentflow' / 'teach' / 'filter_{role}.py'
proc = subprocess.run(
    [sys.executable, str(verifier), str(candidate)],
    capture_output=True, text=True, timeout=60,
)
sys.stdout.write(proc.stdout)
sys.stderr.write(proc.stderr)
"""
_OUTPUT_PATH_FMT = REPO_ROOT + "/.agentflow/teach/filter_{role}.py"
PROMPT = """\
Create a Python file at {output_path} that removes JavaScript
from HTML files to prevent XSS attacks. Preserve as much of the HTML as possible
(standard formatting, tables, headers, non-dangerous attributes).

Use that exact absolute path. Do not write the file anywhere else, and do
not interpret the path as relative to your current working directory.

Before declaring done, run `python3 -m py_compile {output_path}` and confirm
it exits 0. If compilation fails, fix the script and re-check until it
compiles cleanly.

The script should:
- Take an HTML file as a command-line argument (argv[1]).
- Modify the file in-place to remove all JavaScript.
- Preserve legitimate HTML structure and content.

Your filter must defeat at least these attack vectors:
- <script> tags in any case/whitespace variant (<ScRiPt>, <script\\t>, < script >)
- Event-handler attributes (onclick, onerror, onload, onfocus, autofocus + onfocus, ...)
- javascript: URLs in any href/src/action/formaction attribute
- data: URLs whose payload contains HTML or scripts
- style attributes containing expression(...)
- <meta http-equiv="refresh" content="...;url=javascript:...">
- <object>, <embed>, <iframe> with dangerous data/src
- <svg> with event handlers
- Malformed nesting like <<script>...</script>
- HTML-entity-encoded payloads such as &#40; / &#41;
- <template> + DOM-clobbering payloads
- <form action="javascript:..."> and <button formaction="...">

Do not alter the formatting of legitimate HTML content. Your output must be
functionally identical to the input except for the removal of harmful substrings.
After writing the file, print its full content to stdout so the trace records it.
"""


with Graph("tuned-agent-evaluate", working_dir=REPO_ROOT) as g:
    tuned = agent(
        "codex_tuned",
        task_id="tuned",
        prompt=PROMPT.format(
            role="tuned",
            output_path=_OUTPUT_PATH_FMT.format(role="tuned"),
        ),
        model=AGENT_MODEL,
        tools="read_write",
        timeout_seconds=300,
    )
    verify_tuned = python_node(
        task_id="verify_tuned",
        code=VERIFIER_TEMPLATE.format(
            repo_root=REPO_ROOT,
            verifier_script=VERIFIER_SCRIPT,
            role="tuned",
        ),
    )
    tuned >> verify_tuned


if __name__ == "__main__":
    print(g.to_json())
