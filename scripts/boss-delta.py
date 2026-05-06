#!/usr/bin/env python3
"""boss-delta.py — diff requirements.md against git HEAD, output run-plan.md.

Usage:
    python scripts/boss-delta.py [--requirements .boss/requirements.md] [--output .boss/run-plan.md]

Exit codes:
    0 — success (run-plan.md written)
    1 — fatal error
"""
import argparse
import datetime
import json
import re
import subprocess
import sys
from pathlib import Path

LAYER_PATTERN = re.compile(r'^###\s+Layer\s+\d+[:\s]+(.*)', re.MULTILINE)
REQ_PATTERN = re.compile(r'\|\s*(REQ-\d+|REQ-NFR-\d+)\s*\|')


def git_show_head(path: Path) -> str | None:
    """Return git HEAD content of path, or None if not tracked."""
    try:
        result = subprocess.run(
            ["git", "show", f"HEAD:{path}"],
            capture_output=True, text=True, check=False,
            cwd=path.parent.parent if path.name == "requirements.md" else Path.cwd(),
        )
        if result.returncode == 0:
            return result.stdout
        return None
    except FileNotFoundError:
        return None


def parse_req_ids(text: str) -> set[str]:
    return set(REQ_PATTERN.findall(text))


def parse_layers(text: str) -> dict[str, list[str]]:
    """Map layer name → list of REQ IDs in that layer."""
    layers: dict[str, list[str]] = {}
    current_layer = "Preamble"
    for line in text.splitlines():
        m = LAYER_PATTERN.match(line)
        if m:
            current_layer = m.group(1).strip()
            layers.setdefault(current_layer, [])
        elif REQ_PATTERN.search(line):
            for req in REQ_PATTERN.findall(line):
                layers.setdefault(current_layer, []).append(req)
    return layers


def diff_req_ids(old_text: str | None, new_text: str) -> tuple[set, set, set]:
    """Return (added, removed, unchanged) REQ ID sets."""
    new_ids = parse_req_ids(new_text)
    if old_text is None:
        return new_ids, set(), set()
    old_ids = parse_req_ids(old_text)
    added = new_ids - old_ids
    removed = old_ids - new_ids
    unchanged = old_ids & new_ids
    # Detect modified reqs: same ID but different line text
    modified = set()
    old_lines = {m: "" for m in old_ids}
    new_lines = {m: "" for m in new_ids}
    for line in old_text.splitlines():
        for req in REQ_PATTERN.findall(line):
            old_lines[req] = line
    for line in new_text.splitlines():
        for req in REQ_PATTERN.findall(line):
            new_lines[req] = line
    for req in unchanged:
        if old_lines.get(req) != new_lines.get(req):
            modified.add(req)
    return added | modified, removed, unchanged - modified


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--requirements", default=".boss/requirements.md")
    parser.add_argument("--output", default=".boss/run-plan.md")
    args = parser.parse_args()

    req_path = Path(args.requirements)
    out_path = Path(args.output)

    if not req_path.exists():
        print(f"ERROR: {req_path} not found", file=sys.stderr)
        return 1

    new_text = req_path.read_text(encoding="utf-8")
    old_text = git_show_head(req_path)

    changed_ids, removed_ids, unchanged_ids = diff_req_ids(old_text, new_text)
    layers = parse_layers(new_text)

    affected_layers: list[str] = []
    for layer, reqs in layers.items():
        if any(r in changed_ids or r in removed_ids for r in reqs):
            affected_layers.append(layer)

    is_first_run = old_text is None
    ts = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

    lines = [
        f"# BOSS Run Plan",
        f"_Generated: {ts}_",
        f"",
    ]
    if is_first_run:
        lines += [
            "## Status: FULL RUN (requirements.md not yet in git)",
            "",
            "Run all phases. No baseline to diff against.",
            "",
        ]
    elif not changed_ids and not removed_ids:
        lines += [
            "## Status: NO CHANGES",
            "",
            "requirements.md identical to HEAD. No phases need re-running.",
            "",
        ]
    else:
        lines += [
            f"## Status: PARTIAL RUN ({len(changed_ids)} changed, {len(removed_ids)} removed)",
            "",
            "### Changed / Added Requirements",
        ]
        for r in sorted(changed_ids):
            lines.append(f"- {r}")
        if removed_ids:
            lines += ["", "### Removed Requirements"]
            for r in sorted(removed_ids):
                lines.append(f"- {r}")
        lines += [
            "",
            "### Affected Phases (re-run these)",
        ]
        for layer in affected_layers:
            lines.append(f"- {layer}")
        if not affected_layers:
            lines.append("- (none — all changes are in NFR or metadata)")
        lines += [
            "",
            "### Unchanged Phases (skip unless dependencies changed)",
        ]
        skipped = [l for l in layers if l not in affected_layers]
        for layer in skipped:
            lines.append(f"- {layer}")

    lines += [
        "",
        "---",
        "_Run `python scripts/boss-delta.py` after updating requirements.md to refresh this file._",
    ]

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"BOSS delta: run-plan written to {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
