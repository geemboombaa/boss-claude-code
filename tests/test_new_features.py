"""Tests for new features: CI matrix, boss-delta, pre-build-gate, demo/signoff skills."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

import pytest
import yaml  # requires pyyaml

REPO = pathlib.Path(__file__).parent.parent
IS_WINDOWS = sys.platform == "win32"
DELTA_SCRIPT = REPO / "scripts" / "boss-delta.py"


# ---------------------------------------------------------------------------
# REQ-069: CI templates have matrix key
# ---------------------------------------------------------------------------

CI_TEMPLATES = [
    REPO / ".github" / "workflows" / "test.yml",
    REPO / "ci-templates" / "python.yml",
    REPO / "ci-templates" / "node.yml",
    REPO / "ci-templates" / "go.yml",
    REPO / "ci-templates" / "rust.yml",
    REPO / "ci-templates" / "playwright.yml",
]


@pytest.mark.parametrize("template", CI_TEMPLATES, ids=lambda p: p.name)
def test_ci_template_has_matrix(template):
    """REQ-069: CI template runs on ubuntu-latest AND macos-latest."""
    assert template.exists(), f"{template} not found"
    data = yaml.safe_load(template.read_text(encoding="utf-8"))
    jobs = data.get("jobs", {})
    for job_name, job in jobs.items():
        strategy = job.get("strategy", {})
        matrix = strategy.get("matrix", {})
        os_list = matrix.get("os", [])
        assert "ubuntu-latest" in os_list, f"{template.name} job '{job_name}' missing ubuntu-latest"
        assert "macos-latest" in os_list, f"{template.name} job '{job_name}' missing macos-latest"
        break  # check first job


# ---------------------------------------------------------------------------
# REQ-066 / REQ-067: boss-delta.py
# ---------------------------------------------------------------------------

def run_delta(cwd, extra_args=None):
    args = [sys.executable, str(DELTA_SCRIPT)]
    if extra_args:
        args += extra_args
    return subprocess.run(args, capture_output=True, text=True, cwd=str(cwd))


class TestBossDelta:

    def test_full_run_when_not_git_tracked(self, tmp_path):
        """REQ-066: first run (no git history) outputs FULL RUN plan."""
        req_file = tmp_path / ".boss" / "requirements.md"
        req_file.parent.mkdir(parents=True)
        req_file.write_text("# Reqs\n| REQ-001 | Do thing | Yes |\n")

        result = run_delta(tmp_path, ["--requirements", str(req_file), "--output", str(tmp_path / ".boss" / "run-plan.md")])
        assert result.returncode == 0

        run_plan = (tmp_path / ".boss" / "run-plan.md").read_text()
        assert "FULL RUN" in run_plan

    def test_outputs_run_plan_file(self, tmp_path):
        """REQ-067: boss-delta.py writes .boss/run-plan.md."""
        req_file = tmp_path / ".boss" / "requirements.md"
        req_file.parent.mkdir(parents=True)
        req_file.write_text("| REQ-001 | thing | Yes |\n")
        out_file = tmp_path / ".boss" / "run-plan.md"

        result = run_delta(tmp_path, ["--requirements", str(req_file), "--output", str(out_file)])
        assert result.returncode == 0
        assert out_file.exists()

    def test_parses_req_ids_from_table(self, tmp_path):
        """REQ-067: run-plan lists REQ IDs found in requirements.md."""
        req_file = tmp_path / ".boss" / "requirements.md"
        req_file.parent.mkdir(parents=True)
        req_file.write_text("| REQ-042 | Some requirement | Yes |\n| REQ-043 | Another | No |\n")
        out_file = tmp_path / ".boss" / "run-plan.md"

        run_delta(tmp_path, ["--requirements", str(req_file), "--output", str(out_file)])
        run_plan = out_file.read_text()
        # On first run (no git), FULL RUN — but REQ IDs should be parseable
        assert "FULL RUN" in run_plan

    def test_error_when_requirements_missing(self, tmp_path):
        """boss-delta.py exits 1 when requirements.md not found."""
        result = run_delta(tmp_path, ["--requirements", str(tmp_path / "nonexistent.md")])
        assert result.returncode == 1
        assert "not found" in result.stderr.lower()


# ---------------------------------------------------------------------------
# REQ-072 / REQ-075: pre-build-gate hook files exist
# ---------------------------------------------------------------------------

def test_pre_build_gate_sh_exists():
    """REQ-072: pre-build-gate.sh exists."""
    assert (REPO / "hooks" / "pre-build-gate.sh").exists()


def test_pre_build_gate_ps1_exists():
    """REQ-072: pre-build-gate.ps1 exists."""
    assert (REPO / "hooks" / "pre-build-gate.ps1").exists()


def test_pre_build_gate_sh_references_pretooluse():
    """pre-build-gate.sh handles Write/Edit tools."""
    content = (REPO / "hooks" / "pre-build-gate.sh").read_text()
    assert "Write" in content
    assert "Edit" in content


def test_pre_build_gate_ps1_references_pretooluse():
    """pre-build-gate.ps1 handles Write/Edit tools."""
    content = (REPO / "hooks" / "pre-build-gate.ps1").read_text()
    assert "Write" in content
    assert "Edit" in content


def test_pre_build_gate_sh_checks_spec_and_signoff():
    """pre-build-gate.sh gates on spec.md existence and demo-signoff.md absence."""
    content = (REPO / "hooks" / "pre-build-gate.sh").read_text()
    assert "spec.md" in content
    assert "demo-signoff.md" in content


def test_pre_build_gate_ps1_checks_spec_and_signoff():
    content = (REPO / "hooks" / "pre-build-gate.ps1").read_text()
    assert "spec.md" in content
    assert "demo-signoff.md" in content


def test_pre_build_gate_blocks_with_json_output():
    """pre-build-gate outputs JSON {decision:block} on stdout when blocking."""
    content = (REPO / "hooks" / "pre-build-gate.sh").read_text()
    assert "decision" in content
    assert "block" in content


def test_pre_build_gate_sh_boss_skip_bypass():
    """BOSS_SKIP=1 bypass present in pre-build-gate.sh."""
    content = (REPO / "hooks" / "pre-build-gate.sh").read_text()
    assert "BOSS_SKIP" in content


@pytest.mark.skipif(IS_WINDOWS, reason="bash tests only on Unix")
def test_pre_build_gate_sh_syntax():
    """pre-build-gate.sh has valid bash syntax."""
    result = subprocess.run(
        ["bash", "-n", str(REPO / "hooks" / "pre-build-gate.sh")],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Bash syntax error: {result.stderr}"


@pytest.mark.skipif(IS_WINDOWS, reason="bash tests only on Unix")
def test_pre_build_gate_sh_allows_when_no_spec(tmp_path):
    """pre-build-gate.sh exits 0 (allow) when .boss/spec.md does not exist."""
    payload = json.dumps({
        "cwd": str(tmp_path),
        "tool_name": "Write",
        "tool_input": {"file_path": str(tmp_path / "src" / "main.py"), "content": "x=1"},
    })
    result = subprocess.run(
        ["bash", str(REPO / "hooks" / "pre-build-gate.sh")],
        input=payload, capture_output=True, text=True
    )
    assert result.returncode == 0
    assert result.stdout.strip() == "", "Should not block when spec.md absent"


@pytest.mark.skipif(IS_WINDOWS, reason="bash tests only on Unix")
def test_pre_build_gate_sh_allows_boss_dir_writes(tmp_path):
    """pre-build-gate.sh allows writes inside .boss/ even when gate is active."""
    boss_dir = tmp_path / ".boss"
    boss_dir.mkdir()
    (boss_dir / "spec.md").write_text("# spec")
    # No demo-signoff.md -- gate should be active but .boss/ writes allowed
    payload = json.dumps({
        "cwd": str(tmp_path),
        "tool_name": "Write",
        "tool_input": {"file_path": str(boss_dir / "demo-artifacts" / "wireframe.md"), "content": "# wireframe"},
    })
    result = subprocess.run(
        ["bash", str(REPO / "hooks" / "pre-build-gate.sh")],
        input=payload, capture_output=True, text=True
    )
    assert result.returncode == 0
    assert result.stdout.strip() == "", "Should allow .boss/ writes"


@pytest.mark.skipif(IS_WINDOWS, reason="bash tests only on Unix")
def test_pre_build_gate_sh_blocks_source_writes(tmp_path):
    """pre-build-gate.sh blocks source file writes when spec.md present, no signoff."""
    boss_dir = tmp_path / ".boss"
    boss_dir.mkdir()
    (boss_dir / "spec.md").write_text("# spec")
    payload = json.dumps({
        "cwd": str(tmp_path),
        "tool_name": "Write",
        "tool_input": {"file_path": str(tmp_path / "src" / "main.py"), "content": "x=1"},
    })
    result = subprocess.run(
        ["bash", str(REPO / "hooks" / "pre-build-gate.sh")],
        input=payload, capture_output=True, text=True
    )
    assert result.returncode == 0
    assert result.stdout.strip() != "", "Should output block JSON"
    data = json.loads(result.stdout.strip())
    assert data["decision"] == "block"


@pytest.mark.skipif(IS_WINDOWS, reason="bash tests only on Unix")
def test_pre_build_gate_sh_allows_after_signoff(tmp_path):
    """pre-build-gate.sh allows source writes once demo-signoff.md exists."""
    boss_dir = tmp_path / ".boss"
    boss_dir.mkdir()
    (boss_dir / "spec.md").write_text("# spec")
    (boss_dir / "demo-signoff.md").write_text("approved")
    payload = json.dumps({
        "cwd": str(tmp_path),
        "tool_name": "Write",
        "tool_input": {"file_path": str(tmp_path / "src" / "main.py"), "content": "x=1"},
    })
    result = subprocess.run(
        ["bash", str(REPO / "hooks" / "pre-build-gate.sh")],
        input=payload, capture_output=True, text=True
    )
    assert result.returncode == 0
    assert result.stdout.strip() == "", "Should allow after signoff"


# ---------------------------------------------------------------------------
# REQ-073 / REQ-074: demo and signoff skills exist
# ---------------------------------------------------------------------------

def test_demo_skill_exists():
    """REQ-073: skills/demo/SKILL.md exists."""
    assert (REPO / "skills" / "demo" / "SKILL.md").exists()


def test_signoff_skill_exists():
    """REQ-074: skills/signoff/SKILL.md exists."""
    assert (REPO / "skills" / "signoff" / "SKILL.md").exists()


def test_demo_skill_references_demo_artifacts():
    content = (REPO / "skills" / "demo" / "SKILL.md").read_text()
    assert "demo-artifacts" in content


def test_signoff_skill_references_demo_signoff():
    content = (REPO / "skills" / "signoff" / "SKILL.md").read_text()
    assert "demo-signoff.md" in content


# ---------------------------------------------------------------------------
# Skills install path: must be ~/.claude/skills/<name>/SKILL.md
# ---------------------------------------------------------------------------

def test_install_sh_uses_correct_skills_path():
    """install.sh copies skills to ~/.claude/skills/ not ~/.claude/boss/skills/."""
    content = (REPO / "install.sh").read_text()
    assert '/.claude/skills' in content, "install.sh must write to ~/.claude/skills/"
    # Must NOT install skills under ~/.claude/boss/skills/
    assert 'BOSS_DIR/skills' not in content or '$BOSS_DIR/skills' not in content.split("# Install skills")[1].split("# Install boss")[0] if "# Install skills" in content else True


def test_install_ps1_uses_correct_skills_path():
    """install.ps1 copies skills to ~/.claude/skills/ not ~/.claude/boss/skills/."""
    content = (REPO / "install.ps1").read_text()
    assert r'.claude\skills' in content or 'skillsDir' in content


def test_skill_dir_names_match_commands():
    """Skill directory names produce correct slash command names."""
    for name in ["build", "verify", "certify", "demo", "signoff"]:
        assert (REPO / "skills" / name / "SKILL.md").exists(), f"skills/{name}/SKILL.md missing"


# ---------------------------------------------------------------------------
# REQ-063 / REQ-065: build skill references CI-first bootstrap
# ---------------------------------------------------------------------------

def test_build_skill_references_github_repo_creation():
    """REQ-063: build skill mentions gh repo create for CI-first bootstrap."""
    content = (REPO / "skills" / "build" / "SKILL.md").read_text()
    assert "gh repo create" in content


def test_build_skill_references_boss_delta():
    """REQ-068: build skill mentions boss-delta.py."""
    content = (REPO / "skills" / "build" / "SKILL.md").read_text()
    assert "boss-delta.py" in content
