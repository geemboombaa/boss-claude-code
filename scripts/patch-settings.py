#!/usr/bin/env python3
"""
BOSS settings patcher -- merges Stop/SubagentStop/PreToolUse hooks into ~/.claude/settings.json
Safe: idempotent, non-destructive, atomic write, timestamped backup
"""
import json
import os
import pathlib
import platform
import shutil
import sys
import argparse
import tempfile
from datetime import datetime, timezone


def atomic_write(path: pathlib.Path, content: str) -> None:
    """Write atomically using temp file + rename (FIX ISSUE-006: TOCTOU)."""
    dir_ = path.parent
    dir_.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=dir_, prefix=".settings_tmp_")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp_path, path)  # atomic on POSIX and Windows (same drive)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def timestamped_backup(path: pathlib.Path) -> pathlib.Path:
    """Create timestamped backup (FIX ISSUE-006: single .bak gets overwritten)."""
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup = path.with_name(f"{path.stem}.{ts}.bak")
    shutil.copy2(path, backup)
    return backup


def main():
    parser = argparse.ArgumentParser(description="Patch Claude Code settings.json for BOSS hooks")
    parser.add_argument("--settings", default=None)
    parser.add_argument("--hook-command-sh",  default="bash ~/.claude/boss/hooks/stop-gate.sh")
    parser.add_argument("--hook-command-ps1", default='powershell -ExecutionPolicy Bypass -File "~/.claude/boss/hooks/stop-gate.ps1"')
    parser.add_argument("--pre-build-gate-sh",  default="bash ~/.claude/boss/hooks/pre-build-gate.sh")
    parser.add_argument("--pre-build-gate-ps1", default='powershell -ExecutionPolicy Bypass -File "~/.claude/boss/hooks/pre-build-gate.ps1"')
    parser.add_argument("--test-guard-sh",  default="bash ~/.claude/boss/hooks/test-guard.sh")
    parser.add_argument("--test-guard-ps1", default='powershell -ExecutionPolicy Bypass -File "~/.claude/boss/hooks/test-guard.ps1"')
    parser.add_argument("--auto-push-sh",  default="bash ~/.claude/boss/hooks/auto-push.sh")
    parser.add_argument("--auto-push-ps1", default='powershell -ExecutionPolicy Bypass -File "~/.claude/boss/hooks/auto-push.ps1"')
    parser.add_argument("--platform", default=None, choices=["win", "unix"])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    is_windows = (args.platform == "win") or (args.platform is None and platform.system() == "Windows")
    hook_command = args.hook_command_ps1 if is_windows else args.hook_command_sh
    pre_build_gate_command = args.pre_build_gate_ps1 if is_windows else args.pre_build_gate_sh
    test_guard_command = args.test_guard_ps1 if is_windows else args.test_guard_sh
    auto_push_command = args.auto_push_ps1 if is_windows else args.auto_push_sh

    settings_path = (
        pathlib.Path(args.settings) if args.settings
        else pathlib.Path.home() / ".claude" / "settings.json"
    )

    if settings_path.exists():
        raw = settings_path.read_text(encoding="utf-8")
        try:
            settings = json.loads(raw)
        except json.JSONDecodeError as e:
            print(f"ERROR: {settings_path} contains invalid JSON: {e}", file=sys.stderr)
            print(f"  Please fix the JSON manually, then re-run.", file=sys.stderr)
            sys.exit(1)
    else:
        settings = {}

    stop_hook_entry = {
        "matcher": "",
        "hooks": [{"type": "command", "command": hook_command}]
    }
    pre_build_gate_entry = {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [{"type": "command", "command": pre_build_gate_command}]
    }
    test_guard_entry = {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [{"type": "command", "command": test_guard_command}]
    }
    auto_push_entry = {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": auto_push_command}]
    }

    existing_hooks = settings.get("hooks", {})
    changed = False

    for event in ("Stop", "SubagentStop"):
        existing_list = existing_hooks.get(event, [])
        already_registered = any(
            "stop-gate" in h.get("command", "").lower()
            for entry in existing_list
            for h in entry.get("hooks", [])
            if isinstance(h, dict)
        )
        if not already_registered:
            existing_list.append(stop_hook_entry)
            existing_hooks[event] = existing_list
            changed = True
            print(f"  + Adding BOSS stop-gate hook to {event}")
        else:
            print(f"  = BOSS stop-gate hook already registered for {event}, skipping")

    # Register PreToolUse demo/signoff gate
    pre_tool_list = existing_hooks.get("PreToolUse", [])
    gate_registered = any(
        "pre-build-gate" in h.get("command", "").lower()
        for entry in pre_tool_list
        for h in entry.get("hooks", [])
        if isinstance(h, dict)
    )
    if not gate_registered:
        pre_tool_list.append(pre_build_gate_entry)
        existing_hooks["PreToolUse"] = pre_tool_list
        changed = True
        print("  + Adding BOSS pre-build-gate hook to PreToolUse")
    else:
        print("  = BOSS pre-build-gate hook already registered for PreToolUse, skipping")

    guard_registered = any(
        "test-guard" in h.get("command", "").lower()
        for entry in pre_tool_list
        for h in entry.get("hooks", [])
        if isinstance(h, dict)
    )
    if not guard_registered:
        pre_tool_list.append(test_guard_entry)
        existing_hooks["PreToolUse"] = pre_tool_list
        changed = True
        print("  + Adding BOSS test-guard hook to PreToolUse")
    else:
        print("  = BOSS test-guard hook already registered for PreToolUse, skipping")

    # Register PostToolUse Bash hook for auto-push
    post_tool_list = existing_hooks.get("PostToolUse", [])
    auto_push_registered = any(
        "auto-push" in h.get("command", "").lower()
        for entry in post_tool_list
        for h in entry.get("hooks", [])
        if isinstance(h, dict)
    )
    if not auto_push_registered:
        post_tool_list.append(auto_push_entry)
        existing_hooks["PostToolUse"] = post_tool_list
        changed = True
        print("  + Adding BOSS auto-push hook to PostToolUse")
    else:
        print("  = BOSS auto-push hook already registered for PostToolUse, skipping")

    if not changed:
        print("No changes needed -- all BOSS hooks already registered.")
        return

    settings["hooks"] = existing_hooks
    output = json.dumps(settings, indent=2)

    if args.dry_run:
        print("DRY RUN -- would write:")
        print(output)
        return

    if settings_path.exists():
        backup = timestamped_backup(settings_path)
        print(f"  Backed up to {backup}")

    atomic_write(settings_path, output)
    print(f"  Written to {settings_path}")


if __name__ == "__main__":
    main()
