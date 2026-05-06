#!/usr/bin/env python3
"""
BOSS settings patcher -- merges Stop/SubagentStop hooks into ~/.claude/settings.json
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
    parser.add_argument("--platform", default=None, choices=["win", "unix"])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    is_windows = (args.platform == "win") or (args.platform is None and platform.system() == "Windows")
    hook_command = args.hook_command_ps1 if is_windows else args.hook_command_sh

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

    boss_hook_entry = {
        "matcher": "",
        "hooks": [{"type": "command", "command": hook_command}]
    }

    existing_hooks = settings.get("hooks", {})
    changed = False

    for event in ("Stop", "SubagentStop"):
        existing_list = existing_hooks.get(event, [])
        # FIX: check command field only — avoids false match on paths like /home/bossanova/
        already_registered = any(
            "stop-gate" in h.get("command", "").lower()
            for entry in existing_list
            for h in entry.get("hooks", [])
            if isinstance(h, dict)
        )
        if not already_registered:
            existing_list.append(boss_hook_entry)
            existing_hooks[event] = existing_list
            changed = True
            print(f"  + Adding BOSS hook to {event}")
        else:
            print(f"  = BOSS hook already registered for {event}, skipping")

    if not changed:
        print("No changes needed -- BOSS hooks already registered.")
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
