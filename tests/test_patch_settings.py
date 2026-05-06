"""Tests for scripts/patch-settings.py"""
import json
import pathlib
import subprocess
import sys
import tempfile
import os
import pytest

SCRIPT = pathlib.Path(__file__).parent.parent / "scripts" / "patch-settings.py"


def run_patcher(settings_path=None, extra_args=None, platform="unix"):
    args = [sys.executable, str(SCRIPT), f"--platform={platform}"]
    if settings_path:
        args += ["--settings", str(settings_path)]
    if extra_args:
        args += extra_args
    result = subprocess.run(args, capture_output=True, text=True)
    return result


class TestPatchSettings:

    def test_creates_settings_when_missing(self, tmp_path):
        settings = tmp_path / "settings.json"
        result = run_patcher(settings)
        assert result.returncode == 0
        assert settings.exists()
        data = json.loads(settings.read_text())
        assert "hooks" in data
        assert "Stop" in data["hooks"]
        assert "SubagentStop" in data["hooks"]

    def test_idempotent_no_duplicates(self, tmp_path):
        settings = tmp_path / "settings.json"
        # Run twice
        run_patcher(settings)
        run_patcher(settings)
        data = json.loads(settings.read_text())
        # Should have exactly 1 BOSS entry per event
        for event in ("Stop", "SubagentStop"):
            boss_entries = [
                h for entry in data["hooks"][event]
                for h in entry.get("hooks", [])
                if "boss" in str(h).lower() or "stop-gate" in str(h).lower()
            ]
            assert len(boss_entries) == 1, f"Expected 1 BOSS entry for {event}, got {len(boss_entries)}"

    def test_preserves_existing_hooks(self, tmp_path):
        settings = tmp_path / "settings.json"
        existing = {
            "hooks": {
                "Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "echo existing"}]}]
            },
            "otherSetting": "preserved"
        }
        settings.write_text(json.dumps(existing))
        run_patcher(settings)
        data = json.loads(settings.read_text())
        # Existing hook still there
        existing_cmds = [h["command"] for e in data["hooks"]["Stop"] for h in e.get("hooks", [])]
        assert "echo existing" in existing_cmds
        # BOSS hook added
        assert any("boss" in c.lower() or "stop-gate" in c.lower() for c in existing_cmds)
        # Other settings preserved
        assert data["otherSetting"] == "preserved"

    def test_creates_timestamped_backup(self, tmp_path):
        settings = tmp_path / "settings.json"
        settings.write_text('{"hooks": {}}')
        run_patcher(settings)
        backups = list(tmp_path.glob("settings.*.bak"))
        assert len(backups) == 1

    def test_handles_malformed_json(self, tmp_path):
        settings = tmp_path / "settings.json"
        settings.write_text("{not valid json")
        result = run_patcher(settings)
        assert result.returncode == 1
        assert "invalid JSON" in result.stderr
        # Original file not corrupted
        assert settings.read_text() == "{not valid json"

    def test_dry_run_makes_no_changes(self, tmp_path):
        settings = tmp_path / "settings.json"
        original = '{"existing": true}'
        settings.write_text(original)
        run_patcher(settings, extra_args=["--dry-run"])
        assert settings.read_text() == original

    def test_no_backup_when_file_not_exists(self, tmp_path):
        settings = tmp_path / "settings.json"
        run_patcher(settings)
        backups = list(tmp_path.glob("*.bak"))
        assert len(backups) == 0

    def test_windows_uses_ps1_command(self, tmp_path):
        settings = tmp_path / "settings.json"
        run_patcher(settings, platform="win")
        data = json.loads(settings.read_text())
        all_commands = [
            h["command"]
            for event in ("Stop", "SubagentStop")
            for entry in data["hooks"][event]
            for h in entry.get("hooks", [])
        ]
        assert any(".ps1" in c for c in all_commands), "Windows should use .ps1 hook"

    def test_unix_uses_sh_command(self, tmp_path):
        settings = tmp_path / "settings.json"
        run_patcher(settings, platform="unix")
        data = json.loads(settings.read_text())
        all_commands = [
            h["command"]
            for event in ("Stop", "SubagentStop")
            for entry in data["hooks"][event]
            for h in entry.get("hooks", [])
        ]
        assert any(".sh" in c for c in all_commands), "Unix should use .sh hook"

    def test_creates_parent_dirs(self, tmp_path):
        settings = tmp_path / "deeply" / "nested" / "settings.json"
        result = run_patcher(settings)
        assert result.returncode == 0
        assert settings.exists()
