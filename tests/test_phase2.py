"""Tests for Phase 2 enhancements: Layers 12-16."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

import pytest

REPO = pathlib.Path(__file__).parent.parent
IS_WINDOWS = sys.platform == "win32"
HOOKS = REPO / "hooks"


# ---------------------------------------------------------------------------
# Layer 12: Stop hook new env vars present in scripts
# ---------------------------------------------------------------------------

def test_stop_gate_sh_has_boss_retry():
    """REQ-076: BOSS_RETRY logic present in stop-gate.sh."""
    content = (HOOKS / "stop-gate.sh").read_text()
    assert "BOSS_RETRY" in content

def test_stop_gate_sh_has_skip_patterns():
    """REQ-077: BOSS_SKIP_PATTERNS logic present in stop-gate.sh."""
    content = (HOOKS / "stop-gate.sh").read_text()
    assert "BOSS_SKIP_PATTERNS" in content

def test_stop_gate_sh_has_webhook():
    """REQ-078: BOSS_WEBHOOK_URL logic present in stop-gate.sh."""
    content = (HOOKS / "stop-gate.sh").read_text()
    assert "BOSS_WEBHOOK_URL" in content
    assert "curl" in content

def test_stop_gate_ps1_has_boss_retry():
    content = (HOOKS / "stop-gate.ps1").read_text()
    assert "BOSS_RETRY" in content or "bossRetry" in content

def test_stop_gate_ps1_has_skip_patterns():
    content = (HOOKS / "stop-gate.ps1").read_text()
    assert "BOSS_SKIP_PATTERNS" in content

def test_stop_gate_ps1_has_webhook():
    content = (HOOKS / "stop-gate.ps1").read_text()
    assert "BOSS_WEBHOOK_URL" in content

def test_stop_gate_sh_has_coverage():
    """BOSS_COVERAGE=1 opt-in present."""
    content = (HOOKS / "stop-gate.sh").read_text()
    assert "BOSS_COVERAGE" in content
    assert "pytest_cov" in content

def test_stop_gate_ps1_has_coverage():
    content = (HOOKS / "stop-gate.ps1").read_text()
    assert "BOSS_COVERAGE" in content


# ---------------------------------------------------------------------------
# Layer 12: Functional tests (bash-only)
# ---------------------------------------------------------------------------

@pytest.mark.skipif(IS_WINDOWS, reason="bash tests only on Unix")
def test_stop_gate_sh_syntax():
    result = subprocess.run(["bash", "-n", str(HOOKS / "stop-gate.sh")], capture_output=True)
    assert result.returncode == 0, result.stderr.decode()


@pytest.mark.skipif(IS_WINDOWS, reason="bash tests only on Unix")
def test_boss_retry_env_var_read(tmp_path):
    """stop-gate.sh reads BOSS_RETRY without crashing (syntax/logic check)."""
    payload = json.dumps({"cwd": str(tmp_path), "stop_hook_active": False, "session_id": "test"})
    env = {**os.environ, "BOSS_RETRY": "2", "BOSS_SKIP": "1"}
    result = subprocess.run(
        ["bash", str(HOOKS / "stop-gate.sh")],
        input=payload, capture_output=True, text=True, env=env
    )
    assert result.returncode == 0


@pytest.mark.skipif(IS_WINDOWS, reason="bash tests only on Unix")
def test_boss_skip_patterns_exits_open(tmp_path):
    """BOSS_SKIP_PATTERNS skips gate when no git repo (can't determine changed files)."""
    payload = json.dumps({"cwd": str(tmp_path), "stop_hook_active": False, "session_id": "t"})
    env = {**os.environ, "BOSS_SKIP_PATTERNS": "*.md,*.txt"}
    result = subprocess.run(
        ["bash", str(HOOKS / "stop-gate.sh")],
        input=payload, capture_output=True, text=True, env=env
    )
    assert result.returncode == 0
    assert result.stdout.strip() == ""  # no block output


# ---------------------------------------------------------------------------
# Layer 13: test-guard hook
# ---------------------------------------------------------------------------

def test_test_guard_sh_exists():
    assert (HOOKS / "test-guard.sh").exists()

def test_test_guard_ps1_exists():
    assert (HOOKS / "test-guard.ps1").exists()

def test_test_guard_sh_references_baseline():
    content = (HOOKS / "test-guard.sh").read_text()
    assert "baseline-tests.txt" in content
    assert "session_id" in content or "SESSION" in content

def test_test_guard_ps1_references_baseline():
    content = (HOOKS / "test-guard.ps1").read_text()
    assert "baseline-tests.txt" in content

def test_test_guard_blocks_with_json():
    content = (HOOKS / "test-guard.sh").read_text()
    assert "decision" in content
    assert "block" in content

def test_test_guard_sh_boss_skip_bypass():
    content = (HOOKS / "test-guard.sh").read_text()
    assert "BOSS_SKIP" in content

@pytest.mark.skipif(IS_WINDOWS, reason="bash tests only on Unix")
def test_test_guard_sh_syntax():
    result = subprocess.run(["bash", "-n", str(HOOKS / "test-guard.sh")], capture_output=True)
    assert result.returncode == 0, result.stderr.decode()

@pytest.mark.skipif(IS_WINDOWS, reason="bash tests only on Unix")
def test_test_guard_allows_when_no_baseline(tmp_path):
    """test-guard allows Write when no baseline-tests.txt yet AND writes it."""
    payload = json.dumps({
        "cwd": str(tmp_path),
        "tool_name": "Write",
        "tool_input": {"file_path": str(tmp_path / "src" / "main.py"), "content": "x=1"},
        "session_id": "sess-001",
    })
    result = subprocess.run(
        ["bash", str(HOOKS / "test-guard.sh")],
        input=payload, capture_output=True, text=True
    )
    assert result.returncode == 0
    assert result.stdout.strip() == "", "No block on first call (no baseline)"
    # Baseline should now be written
    assert (tmp_path / ".boss" / "baseline-tests.txt").exists()

@pytest.mark.skipif(IS_WINDOWS, reason="bash tests only on Unix")
def test_test_guard_blocks_baseline_file(tmp_path):
    """test-guard blocks edits to files listed in baseline-tests.txt."""
    boss_dir = tmp_path / ".boss"
    boss_dir.mkdir()
    test_file = tmp_path / "tests" / "test_foo.py"
    test_file.parent.mkdir()
    test_file.write_text("def test_foo(): pass")
    baseline = boss_dir / "baseline-tests.txt"
    baseline.write_text(str(test_file) + "\n")
    session_lock = boss_dir / ".baseline_session"
    session_lock.write_text("sess-001")
    payload = json.dumps({
        "cwd": str(tmp_path),
        "tool_name": "Edit",
        "tool_input": {"file_path": str(test_file), "content": ""},
        "session_id": "sess-001",
    })
    result = subprocess.run(
        ["bash", str(HOOKS / "test-guard.sh")],
        input=payload, capture_output=True, text=True
    )
    assert result.returncode == 0
    assert result.stdout.strip() != "", "Should block edit to baseline test"
    data = json.loads(result.stdout.strip())
    assert data["decision"] == "block"

@pytest.mark.skipif(IS_WINDOWS, reason="bash tests only on Unix")
def test_test_guard_allows_non_baseline_file(tmp_path):
    """test-guard allows writes to files NOT in baseline-tests.txt."""
    boss_dir = tmp_path / ".boss"
    boss_dir.mkdir()
    baseline = boss_dir / "baseline-tests.txt"
    baseline.write_text("/some/other/test_file.py\n")
    session_lock = boss_dir / ".baseline_session"
    session_lock.write_text("sess-001")
    payload = json.dumps({
        "cwd": str(tmp_path),
        "tool_name": "Write",
        "tool_input": {"file_path": str(tmp_path / "tests" / "test_new.py"), "content": ""},
        "session_id": "sess-001",
    })
    result = subprocess.run(
        ["bash", str(HOOKS / "test-guard.sh")],
        input=payload, capture_output=True, text=True
    )
    assert result.returncode == 0
    assert result.stdout.strip() == "", "Should allow writes to non-baseline files"


# ---------------------------------------------------------------------------
# Layer 13: test-guard registered in patch-settings.py
# ---------------------------------------------------------------------------

def test_patch_settings_registers_test_guard(tmp_path):
    """REQ-081: test-guard registered as PreToolUse hook."""
    settings = tmp_path / "settings.json"
    subprocess.run(
        [sys.executable, str(REPO / "scripts" / "patch-settings.py"),
         f"--settings={settings}", "--platform=unix"],
        capture_output=True
    )
    data = json.loads(settings.read_text())
    pre_tool = data["hooks"]["PreToolUse"]
    all_cmds = [h["command"] for e in pre_tool for h in e.get("hooks", [])]
    assert any("test-guard" in c for c in all_cmds), "test-guard not in PreToolUse"


# ---------------------------------------------------------------------------
# Layer 14: Verification model
# ---------------------------------------------------------------------------

def test_verify_skill_mandates_stdout():
    """REQ-082: verify/SKILL.md requires reading stdout.txt."""
    content = (REPO / "skills" / "verify" / "SKILL.md").read_text()
    assert "stdout.txt" in content
    assert "mandatory" in content.lower() or "FAIL" in content

def test_certify_skill_extracts_coverage():
    """REQ-084: certify/SKILL.md instructs extracting coverage_pct."""
    content = (REPO / "skills" / "certify" / "SKILL.md").read_text()
    assert "coverage_pct" in content

def test_schema_has_coverage_pct():
    """REQ-083: certification.schema.json has coverage_pct field."""
    schema = json.loads((REPO / ".boss" / "schemas" / "certification.schema.json").read_text())
    assert "coverage_pct" in schema["properties"]
    assert schema["properties"]["coverage_pct"]["type"] == "number"

def test_schema_coverage_pct_range():
    """coverage_pct bounded 0-100."""
    schema = json.loads((REPO / ".boss" / "schemas" / "certification.schema.json").read_text())
    prop = schema["properties"]["coverage_pct"]
    assert prop.get("minimum") == 0
    assert prop.get("maximum") == 100


# ---------------------------------------------------------------------------
# Layer 15: GitHub integrations
# ---------------------------------------------------------------------------

import yaml

CI_TEMPLATES_WITH_COMMENT = [
    REPO / "ci-templates" / "python.yml",
    REPO / "ci-templates" / "node.yml",
    REPO / "ci-templates" / "go.yml",
    REPO / "ci-templates" / "rust.yml",
    REPO / "ci-templates" / "playwright.yml",
]

@pytest.mark.parametrize("template", CI_TEMPLATES_WITH_COMMENT, ids=lambda p: p.name)
def test_ci_template_has_pr_comment_job(template):
    """REQ-085: CI template has comment-pr job."""
    data = yaml.safe_load(template.read_text(encoding="utf-8"))
    jobs = data.get("jobs", {})
    assert "comment-pr" in jobs, f"{template.name} missing comment-pr job"

@pytest.mark.parametrize("template", CI_TEMPLATES_WITH_COMMENT, ids=lambda p: p.name)
def test_ci_template_pr_comment_uses_gh_token(template):
    """PR comment job uses GH_TOKEN for authentication."""
    content = template.read_text()
    assert "GH_TOKEN" in content or "github.token" in content

def test_readme_has_ci_badge():
    """REQ-086: README has CI status badge."""
    content = (REPO / "README.md").read_text()
    assert "badge.svg" in content
    assert "actions/workflows/test.yml" in content


# ---------------------------------------------------------------------------
# Layer 16: Windows/WSL hardening
# ---------------------------------------------------------------------------

def test_install_ps1_has_wsl_detection():
    """REQ-087: install.ps1 detects WSL."""
    content = (REPO / "install.ps1").read_text()
    assert "WSL_DISTRO_NAME" in content or "WSLENV" in content

def test_install_ps1_uses_explicit_ps_path():
    """REQ-088: install.ps1 uses explicit powershell.exe path."""
    content = (REPO / "install.ps1").read_text()
    assert "WindowsPowerShell" in content or "powershell.exe" in content or "psExe" in content

def test_install_ps1_handles_pwsh():
    """install.ps1 prefers pwsh (PS7) when available."""
    content = (REPO / "install.ps1").read_text()
    assert "pwsh" in content
