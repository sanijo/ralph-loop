#!/usr/bin/env python3
"""Stateful, offline subset of gh. Unknown operations fail, never reach GitHub."""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

from support import load, record, save


def option(name, default=None):
    for index, arg in enumerate(args):
        if arg == name:
            return args[index + 1]
        if arg.startswith(name + "="):
            return arg.split("=", 1)[1]
    return default


def body():
    path = option("--body-file")
    if path == "-":
        return sys.stdin.read()
    return Path(path).read_text() if path else option("--body", "")


def issue(number):
    return next(item for item in state["issues"] if item["number"] == int(number))


def labels(item):
    return [label if isinstance(label, str) else label["name"]
            for label in item.get("labels", [])]


def issue_json(item):
    return {**item, "state": item.get("state", "OPEN"),
            "body": item.get("body", ""), "comments": item.get("comments", []),
            "labels": [{"name": label} for label in labels(item)],
            "url": f"https://github.com/fixture/target/issues/{item['number']}"}


def api_issue(item):
    return {**issue_json(item), "state": item.get("state", "OPEN").lower()}


def filtered(items, state_key="state"):
    """Filter like gh's search-backed lists. Issues may carry a stale listedState."""
    requested_state = option("--state", "open").upper()
    wanted_labels = option("--label", "").split(",")
    return [item for item in items
            if (requested_state == "ALL"
                or item.get(state_key, item.get("state", "OPEN")) == requested_state)
            and all(label in labels(item) for label in wanted_labels if label)
            and (not option("--head") or item.get("headRefName") == option("--head"))
            ][:int(option("--limit", "1000"))]


def dispatch():
    if args[:2] == ["auth", "status"]:
        if not state.get("authenticated", True):
            raise ValueError("Fixture gh authentication failed")
        return None
    if args[:2] == ["repo", "view"]:
        return {"nameWithOwner": "fixture/target", "defaultBranchRef": {"name": "main"}}
    if args[:2] == ["issue", "list"]:
        return [issue_json(item) for item in filtered(state["issues"], "listedState")]
    if args[0] == "issue" and args[1] in ("view", "comment", "close", "edit"):
        item = issue(args[2])
        operation = args[1]
        if operation == "comment":
            item.setdefault("comments", []).append({"body": body()})
        elif operation == "close":
            if state.get("listingLag"):
                # The search index has not caught up: listings keep the old state.
                item.setdefault("listedState", item.get("state", "OPEN"))
            item["state"] = "CLOSED"
        elif operation == "edit":
            current = labels(item)
            for label in option("--add-label", "").split(","):
                if label and label not in current:
                    current.append(label)
            removed = option("--remove-label", "").split(",")
            item["labels"] = [label for label in current if label not in removed]
        save(state_path, state)
        return issue_json(item)
    if args[0] == "api":
        endpoint = args[1].removeprefix("/")
        match = re.fullmatch(r"repos/[^/]+/[^/]+/issues/(\d+)(?:/(.*))?", endpoint)
        if not match:
            raise ValueError(f"Unsupported fake gh endpoint: {endpoint}")
        item = issue(match[1])
        relation = match[2]
        if relation == "parent":
            if not item.get("parent"):
                raise ValueError("HTTP 404: no native parent")
            return api_issue(issue(item["parent"]))
        if relation == "dependencies/blocked_by":
            return [api_issue(issue(number)) for number in item.get("blockers", [])]
        if relation == "sub_issues":
            return [api_issue(child) for child in state["issues"]
                    if child.get("parent") == item["number"]]
        if relation == "comments":
            return item.get("comments", [])
        if relation is None:
            return api_issue(item)
        raise ValueError(f"Unsupported fake gh relation: {relation}")
    if args[:2] == ["pr", "list"]:
        return filtered(state["prs"])
    if args[:2] == ["pr", "create"]:
        number = max([pr["number"] for pr in state["prs"]] + [100]) + 1
        item = {"number": number, "title": option("--title"), "body": body(),
                "headRefName": option("--head"), "baseRefName": option("--base", "main"),
                "state": "OPEN", "isDraft": "--draft" in args,
                "url": f"https://github.com/fixture/target/pull/{number}"}
        state["prs"].append(item)
        save(state_path, state)
        return item["url"]
    if args[0] == "pr" and args[1] in ("view", "edit", "ready"):
        item = next(pr for pr in state["prs"]
                    if str(pr["number"]) == args[2] or pr["headRefName"] == args[2])
        if args[1] == "edit":
            item["body"] = body()
        elif args[1] == "ready":
            item["isDraft"] = False
        save(state_path, state)
        return item
    raise ValueError(f"Unsupported fake gh operation: {args}")


record("gh")
args = sys.argv[1:]
state_path = os.environ["RALPH_TEST_STATE"]
state = load(state_path)
try:
    result = dispatch()
    fields = option("--json")
    if fields:
        def project(item):
            return {key: item.get(key) for key in fields.split(",")}
        result = [project(item) for item in result] if isinstance(result, list) else project(result)
    query = option("--jq") or option("-q")
    if query:
        subprocess.run(["jq", "-r", query], input=json.dumps(result), text=True, check=True)
    elif result is not None:
        print(result if isinstance(result, str) else json.dumps(result))
except (ValueError, KeyError, StopIteration, IndexError) as error:
    print(f"fake gh: {error}", file=sys.stderr)
    sys.exit(1)
