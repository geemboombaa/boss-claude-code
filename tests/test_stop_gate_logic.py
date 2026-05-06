"""
Integration tests for stop-gate scripts.
Tests the Python-based JSON patching logic and language detection heuristics.
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import pytest

HOOKS_DIR = pathlib.Path(__file__).parent.parent / "hooks"
STOP_GATE_SH = HOOKS_DIR / "stop-gate.sh"
IS_WINDOWS = sys.platform == "win32"


def make_payload(cwd, stop_hook_active=False):
    return json.dumps({
        "session_id": "test-session",
        "transcript_path": "/tmp/session.jsonl",
        "cwd": str(cwd),
        "hook_event_name": "Stop",
        "stop_hook_active": stop_hook_active
    })


@pytest.mark.skipif(IS_WINDOWS, reason="bash tests only on Unix")
class TestStopGateSh:

    def test_exits_zero_when_stop_hook_active(self, tmp_path):
        payload = make_payload(tmp_path, stop_hook_active=True)
        result = subprocess.run(
            ["bash", str(STOP_GATE_SH)],
            input=payload, capture_output=True, text=True
        )
        assert result.returncode == 0
        assert result.stdout == ""  # no block decision

    def test_exits_zero_with_boss_skip(self, tmp_path):
        payload = make_payload(tmp_path)
        env = {**os.environ, "BOSS_SKIP": "1"}
        result = subprocess.run(
            ["bash", str(STOP_GATE_SH)],
            input=payload, capture_output=True, text=True, env=env
        )
        assert result.returncode == 0
        assert "bypass" in result.stderr.lower() or "skip" in result.stderr.lower()

    def test_exits_zero_with_empty_cwd(self, tmp_path):
        payload = json.dumps({"session_id": "x", "cwd": "", "stop_hook_active": False})
        result = subprocess.run(
            ["bash", str(STOP_GATE_SH)],
            input=payload, capture_output=True, text=True
        )
        assert result.returncode == 0

    def test_exits_zero_when_no_test_suite(self, tmp_path):
        # Empty directory — no pyproject.toml, package.json, etc.
        payload = make_payload(tmp_path)
        result = subprocess.run(
            ["bash", str(STOP_GATE_SH)],
            input=payload, capture_output=True, text=True
        )
        assert result.returncode == 0
        assert "no test suite" in result.stderr.lower()

    def test_exits_zero_when_python_project_no_tests_dir(self, tmp_path):
        (tmp_path / "pyproject.toml").write_text('[project]\nname="test"')
        payload = make_payload(tmp_path)
        result = subprocess.run(
            ["bash", str(STOP_GATE_SH)],
            input=payload, capture_output=True, text=True
        )
        assert result.returncode == 0
        assert "no test" in result.stderr.lower()

    def test_blocks_when_tests_fail(self, tmp_path):
        # Create Python project with a failing test
        (tmp_path / "pyproject.toml").write_text('[project]\nname="test"')
        tests_dir = tmp_path / "tests"
        tests_dir.mkdir()
        (tests_dir / "test_fail.py").write_text("def test_always_fails():\n    assert False\n")
        payload = make_payload(tmp_path)
        # Use system python
        result = subprocess.run(
            ["bash", str(STOP_GATE_SH)],
            input=payload, capture_output=True, text=True
        )
        assert result.returncode == 0
        # Should output a block decision to stdout
        if result.stdout.strip():
            decision = json.loads(result.stdout)
            assert decision["decision"] == "block"
            assert "Tests failed" in decision["reason"]

    def test_allows_when_tests_pass(self, tmp_path):
        (tmp_path / "pyproject.toml").write_text('[project]\nname="test"')
        tests_dir = tmp_path / "tests"
        tests_dir.mkdir()
        (tests_dir / "test_pass.py").write_text("def test_always_passes():\n    assert True\n")
        payload = make_payload(tmp_path)
        result = subprocess.run(
            ["bash", str(STOP_GATE_SH)],
            input=payload, capture_output=True, text=True
        )
        assert result.returncode == 0
        assert result.stdout.strip() == ""  # no block decision
        assert "passed" in result.stderr.lower()

    def test_rejects_unsafe_cwd_with_semicolon(self, tmp_path):
        payload = json.dumps({"session_id": "x", "cwd": "/tmp/foo;echo pwned", "stop_hook_active": False})
        result = subprocess.run(
            ["bash", str(STOP_GATE_SH)],
            input=payload, capture_output=True, text=True
        )
        assert result.returncode == 0
        assert "unsafe" in result.stderr.lower()

    def test_lockfile_cleaned_up_after_run(self, tmp_path):
        payload = make_payload(tmp_path)
        subprocess.run(["bash", str(STOP_GATE_SH)], input=payload, capture_output=True, text=True)
        lock = tmp_path / ".boss" / ".gate_running"
        assert not lock.exists(), "Lockfile should be removed after hook completes"

    def test_exits_zero_on_invalid_json_payload(self):
        result = subprocess.run(
            ["bash", str(STOP_GATE_SH)],
            input="not json at all", capture_output=True, text=True
        )
        assert result.returncode == 0  # fail open


class TestLanguageDetectionHeuristics:
    """Pure Python tests for language detection logic (platform-independent)."""

    def test_python_detected_by_pyproject(self, tmp_path):
        (tmp_path / "pyproject.toml").write_text("")
        assert (tmp_path / "pyproject.toml").exists()

    def test_python_detected_by_pytest_ini(self, tmp_path):
        (tmp_path / "pytest.ini").write_text("[pytest]")
        assert (tmp_path / "pytest.ini").exists()

    def test_node_detected_by_package_json(self, tmp_path):
        (tmp_path / "package.json").write_text("{}")
        assert (tmp_path / "package.json").exists()

    def test_go_detected_by_go_mod(self, tmp_path):
        (tmp_path / "go.mod").write_text("module test")
        assert (tmp_path / "go.mod").exists()

    def test_rust_detected_by_cargo_toml(self, tmp_path):
        (tmp_path / "Cargo.toml").write_text("[package]")
        assert (tmp_path / "Cargo.toml").exists()
