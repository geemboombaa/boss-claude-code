#!/usr/bin/env python3
"""BOSS CI notification webhook — REQ-W13/W14/W15.

Posts to BOSS_NOTIFY webhook URL when CI job completes.
Payload: {event, repo, branch, pr_url, ci_status, test_summary}
Silent no-op if BOSS_NOTIFY not set.
"""
import json
import os
import subprocess
import sys
import urllib.request


def _git(args):
    r = subprocess.run(["git"] + args, capture_output=True, text=True)
    return r.stdout.strip()


def main():
    webhook_url = os.environ.get("BOSS_NOTIFY", "")
    if not webhook_url:
        sys.exit(0)

    repo = _git(["remote", "get-url", "origin"])
    branch = _git(["branch", "--show-current"])
    ci_status = os.environ.get("BOSS_CI_STATUS", "unknown")
    pr_url = os.environ.get("BOSS_PR_URL", "")
    test_summary = os.environ.get("BOSS_TEST_SUMMARY", "")
    event = os.environ.get("BOSS_EVENT", "ci_complete")

    payload = {
        "event": event,
        "repo": repo,
        "branch": branch,
        "pr_url": pr_url,
        "ci_status": ci_status,
        "test_summary": test_summary,
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        webhook_url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        urllib.request.urlopen(req, timeout=10)
    except Exception as e:
        print(f"[BOSS notify] WARNING: webhook POST failed: {e}", file=sys.stderr)
        sys.exit(0)


if __name__ == "__main__":
    main()
