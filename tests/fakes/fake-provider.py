#!/usr/bin/env python3
"""Record a provider invocation and execute a scenario-owned action script."""

import os
import subprocess
import sys
import time
from pathlib import Path

from support import load, record


record(Path(sys.argv[0]).name)
script = load(os.environ["RALPH_TEST_PROVIDER_SCRIPT"])
# A script is one step or a list of steps, e.g. commit then leave dirty files.
steps = script if isinstance(script, list) else [script]
for step in steps:
    action = step["action"]
    if action in ("commit", "dirty"):
        path = Path(step.get("file", "implementation.txt"))
        # Appending lets one script commit again on later iterations.
        with path.open("a" if step.get("append") else "w") as handle:
            handle.write(step.get("content", "implemented\n"))
        if action == "commit":
            subprocess.run(["git", "add", "--", step.get("file", "implementation.txt")],
                           check=True)
            subprocess.run(["git", "commit", "--quiet", "-m",
                            step.get("message", "feat: implement fixture issue")], check=True)
    elif action == "blocker":
        # Prefer an explicit fixture path; later runner scenarios can use its env path.
        path = step.get("path") or os.environ["RALPH_BLOCKER_FILE"]
        Path(path).write_text(step.get("reason", "Fixture needs more information\n"))
    elif action == "hang":
        time.sleep(step.get("seconds", 60))
    elif action == "exit":
        print(step.get("output", "Fixture provider error"), flush=True)
        sys.exit(step.get("code", 1))
    elif action != "noop":
        sys.exit(f"Unsupported fake provider action: {action}")
    if "output" in step:
        print(step["output"], flush=True)
