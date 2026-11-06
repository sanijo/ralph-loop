"""Shared fixture I/O for the offline command-line doubles."""

import json
import os
import sys
from pathlib import Path


def record(tool):
    with open(os.environ["RALPH_TEST_EVENTS"], "a") as events:
        events.write(json.dumps({"tool": tool, "argv": sys.argv[1:],
                                 "cwd": os.getcwd(), "pid": os.getpid()}) + "\n")


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + "\n")
