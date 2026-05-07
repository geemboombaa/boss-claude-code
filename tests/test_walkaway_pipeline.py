"""Tests for walkaway pipeline — REQ-W01 to REQ-W26.

TDD red phase: ALL tests here must FAIL until the walkaway features are built.
Written before any implementation code exists.
"""
import json
import os
import pathlib
import re
import sys

import pytest

REPO = pathlib.Path(__file__).parent.parent
HOOKS = REPO / "hooks"
SKILLS_GLOBAL = pathlib.Path.home() / ".claude" / "skills"
BOSS_GLOBAL = pathlib.Path.home() / ".claude" / "boss"
SETTINGS_PATH = pathlib.Path.home() / ".claude" / "settings.json"
SCHEMAS = REPO / ".boss" / "schemas"
CI_TEMPLATES = REPO / "ci-templates"
IS_WINDOWS = sys.platform == "win32"


# ---------------------------------------------------------------------------
# REQ-W01: PostToolUse hook fires after Bash tool calls containing git commit
# ---------------------------------------------------------------------------

def test_W01_settings_has_posttooluse_hook():
    """REQ-W01: settings.json must have PostToolUse entry matching Bash."""
    settings = json.loads(SETTINGS_PATH.read_text())
    hooks = settings.get("hooks", {})
    assert "PostToolUse" in hooks, "No PostToolUse key in hooks"
    entries = hooks["PostToolUse"]
    assert len(entries) > 0, "PostToolUse hook list is empty"
    matchers = [e.get("matcher", "") for e in entries]
    assert any("Bash" in m for m in matchers), f"No Bash matcher in PostToolUse. Got: {matchers}"


def test_W01_posttooluse_hook_command_references_auto_push():
    """REQ-W01: PostToolUse Bash hook command must reference auto-push script."""
    settings = json.loads(SETTINGS_PATH.read_text())
    hooks = settings.get("hooks", {}).get("PostToolUse", [])
    bash_hooks = [e for e in hooks if "Bash" in e.get("matcher", "")]
    assert bash_hooks, "No Bash PostToolUse hook found"
    commands = []
    for entry in bash_hooks:
        for h in entry.get("hooks", []):
            commands.append(h.get("command", ""))
    assert any("auto-push" in c.lower() or "autopush" in c.lower() for c in commands), \
        f"No auto-push reference in PostToolUse commands. Got: {commands}"


# ---------------------------------------------------------------------------
# REQ-W02: Auto-push hook pushes to boss/<req-slug> after every commit
# ---------------------------------------------------------------------------

def test_W02_auto_push_script_exists():
    """REQ-W02: auto-push script must exist (PS1 or sh)."""
    ps1 = HOOKS / "auto-push.ps1"
    sh = HOOKS / "auto-push.sh"
    assert ps1.exists() or sh.exists(), \
        f"Neither {ps1} nor {sh} exists"


def test_W02_auto_push_script_references_boss_prefix():
    """REQ-W02: auto-push script must push to boss/ prefixed branch."""
    ps1 = HOOKS / "auto-push.ps1"
    sh = HOOKS / "auto-push.sh"
    script = ps1 if ps1.exists() else sh
    if not script.exists():
        pytest.skip("auto-push script not yet created")
    content = script.read_text()
    assert "boss/" in content, "auto-push script must reference boss/ branch prefix"


# ---------------------------------------------------------------------------
# REQ-W03: Branch slug derived from requirement text
# ---------------------------------------------------------------------------

def test_W03_auto_push_derives_slug_from_requirement():
    """REQ-W03: auto-push must read CLAUDE.md requirement section for slug."""
    ps1 = HOOKS / "auto-push.ps1"
    sh = HOOKS / "auto-push.sh"
    script = ps1 if ps1.exists() else sh
    if not script.exists():
        pytest.skip("auto-push script not yet created")
    content = script.read_text()
    assert "CLAUDE.md" in content, "auto-push must read CLAUDE.md for branch slug"


# ---------------------------------------------------------------------------
# REQ-W04: BOSS_BRANCH_PREFIX env var overrides default boss/ prefix
# ---------------------------------------------------------------------------

def test_W04_auto_push_respects_boss_branch_prefix():
    """REQ-W04: BOSS_BRANCH_PREFIX env var must override default prefix."""
    ps1 = HOOKS / "auto-push.ps1"
    sh = HOOKS / "auto-push.sh"
    script = ps1 if ps1.exists() else sh
    if not script.exists():
        pytest.skip("auto-push script not yet created")
    content = script.read_text()
    assert "BOSS_BRANCH_PREFIX" in content, "auto-push must support BOSS_BRANCH_PREFIX env var"


# ---------------------------------------------------------------------------
# REQ-W05: Auto-push creates remote branch with -u origin if not exists
# ---------------------------------------------------------------------------

def test_W05_auto_push_uses_upstream_flag():
    """REQ-W05: auto-push must use -u origin when creating new branch."""
    ps1 = HOOKS / "auto-push.ps1"
    sh = HOOKS / "auto-push.sh"
    script = ps1 if ps1.exists() else sh
    if not script.exists():
        pytest.skip("auto-push script not yet created")
    content = script.read_text()
    assert "-u origin" in content or "--set-upstream" in content, \
        "auto-push must use -u origin to create remote tracking branch"


# ---------------------------------------------------------------------------
# REQ-W06: Auto-push skipped if BOSS_SKIP=1
# ---------------------------------------------------------------------------

def test_W06_auto_push_respects_boss_skip():
    """REQ-W06: auto-push must skip if BOSS_SKIP=1."""
    ps1 = HOOKS / "auto-push.ps1"
    sh = HOOKS / "auto-push.sh"
    script = ps1 if ps1.exists() else sh
    if not script.exists():
        pytest.skip("auto-push script not yet created")
    content = script.read_text()
    assert "BOSS_SKIP" in content, "auto-push must check BOSS_SKIP env var"


# ---------------------------------------------------------------------------
# REQ-W07: Auto-push logs to stderr
# ---------------------------------------------------------------------------

def test_W07_auto_push_logs_to_stderr():
    """REQ-W07: auto-push must log action to stderr."""
    ps1 = HOOKS / "auto-push.ps1"
    sh = HOOKS / "auto-push.sh"
    script = ps1 if ps1.exists() else sh
    if not script.exists():
        pytest.skip("auto-push script not yet created")
    content = script.read_text()
    # PS1: Write-Host with stderr, or [Console]::Error. Bash: >&2
    has_stderr = (">&2" in content or
                  "[Console]::Error" in content or
                  "Write-Error" in content or
                  "Write-Host" in content)
    assert has_stderr, "auto-push must write to stderr (not silent)"


# ---------------------------------------------------------------------------
# REQ-W08: Auto-PR created via gh pr create after first push
# ---------------------------------------------------------------------------

def test_W08_auto_pr_script_exists():
    """REQ-W08: auto-pr script must exist."""
    ps1 = HOOKS / "auto-pr.ps1"
    sh = HOOKS / "auto-pr.sh"
    assert ps1.exists() or sh.exists(), \
        f"Neither {ps1} nor {sh} exists"


def test_W08_auto_pr_calls_gh_pr_create():
    """REQ-W08: auto-pr script must call gh pr create."""
    ps1 = HOOKS / "auto-pr.ps1"
    sh = HOOKS / "auto-pr.sh"
    script = ps1 if ps1.exists() else sh
    if not script.exists():
        pytest.skip("auto-pr script not yet created")
    content = script.read_text()
    assert "gh pr create" in content, "auto-pr must call gh pr create"


# ---------------------------------------------------------------------------
# REQ-W09: PR title = first line of requirement
# ---------------------------------------------------------------------------

def test_W09_auto_pr_uses_requirement_as_title():
    """REQ-W09: auto-pr must set PR title from requirement text."""
    ps1 = HOOKS / "auto-pr.ps1"
    sh = HOOKS / "auto-pr.sh"
    script = ps1 if ps1.exists() else sh
    if not script.exists():
        pytest.skip("auto-pr script not yet created")
    content = script.read_text()
    assert "--title" in content, "auto-pr must use --title with requirement text"
    assert "CLAUDE.md" in content, "auto-pr must read requirement from CLAUDE.md"


# ---------------------------------------------------------------------------
# REQ-W10: PR body contains requirement, spec.md summary, CI badge link
# ---------------------------------------------------------------------------

def test_W10_auto_pr_body_references_spec():
    """REQ-W10: auto-pr body must reference .boss/spec.md."""
    ps1 = HOOKS / "auto-pr.ps1"
    sh = HOOKS / "auto-pr.sh"
    script = ps1 if ps1.exists() else sh
    if not script.exists():
        pytest.skip("auto-pr script not yet created")
    content = script.read_text()
    assert "spec.md" in content, "auto-pr body must reference .boss/spec.md"


# ---------------------------------------------------------------------------
# REQ-W11: PR creation idempotent — skip if PR already exists
# ---------------------------------------------------------------------------

def test_W11_auto_pr_checks_existing_pr():
    """REQ-W11: auto-pr must check if PR exists before creating."""
    ps1 = HOOKS / "auto-pr.ps1"
    sh = HOOKS / "auto-pr.sh"
    script = ps1 if ps1.exists() else sh
    if not script.exists():
        pytest.skip("auto-pr script not yet created")
    content = script.read_text()
    assert "gh pr list" in content or "gh pr view" in content, \
        "auto-pr must check for existing PR before creating"


# ---------------------------------------------------------------------------
# REQ-W12: gh CLI not installed → graceful warning, no crash
# ---------------------------------------------------------------------------

def test_W12_auto_pr_handles_missing_gh():
    """REQ-W12: auto-pr must handle missing gh CLI gracefully."""
    ps1 = HOOKS / "auto-pr.ps1"
    sh = HOOKS / "auto-pr.sh"
    script = ps1 if ps1.exists() else sh
    if not script.exists():
        pytest.skip("auto-pr script not yet created")
    content = script.read_text()
    # Must check if gh exists before calling it
    has_gh_check = ("Get-Command" in content and "gh" in content) or \
                   ("command -v gh" in content) or \
                   ("which gh" in content) or \
                   ("where gh" in content)
    assert has_gh_check, "auto-pr must check if gh CLI is available before use"


# ---------------------------------------------------------------------------
# REQ-W13: BOSS_NOTIFY webhook POSTed when CI job completes
# ---------------------------------------------------------------------------

def test_W13_notify_script_exists():
    """REQ-W13: CI notify script must exist."""
    # Can be in scripts/ or hooks/
    candidates = [
        REPO / "scripts" / "notify.py",
        REPO / "scripts" / "notify.sh",
        REPO / "hooks" / "notify.sh",
        REPO / "hooks" / "notify.ps1",
    ]
    exists = any(p.exists() for p in candidates)
    assert exists, f"No notify script found. Checked: {[str(p) for p in candidates]}"


def test_W13_notify_script_reads_boss_notify_env():
    """REQ-W13: notify script must use BOSS_NOTIFY env var as webhook URL."""
    candidates = [
        REPO / "scripts" / "notify.py",
        REPO / "scripts" / "notify.sh",
        REPO / "hooks" / "notify.sh",
        REPO / "hooks" / "notify.ps1",
    ]
    script = next((p for p in candidates if p.exists()), None)
    if script is None:
        pytest.skip("notify script not yet created")
    content = script.read_text()
    assert "BOSS_NOTIFY" in content, "notify script must use BOSS_NOTIFY env var"


# ---------------------------------------------------------------------------
# REQ-W14: Notification payload has required fields
# ---------------------------------------------------------------------------

def test_W14_notify_payload_has_required_fields():
    """REQ-W14: notify payload must include event, repo, branch, pr_url, ci_status, test_summary."""
    candidates = [
        REPO / "scripts" / "notify.py",
        REPO / "scripts" / "notify.sh",
        REPO / "hooks" / "notify.sh",
        REPO / "hooks" / "notify.ps1",
    ]
    script = next((p for p in candidates if p.exists()), None)
    if script is None:
        pytest.skip("notify script not yet created")
    content = script.read_text()
    required_fields = ["event", "repo", "branch", "pr_url", "ci_status", "test_summary"]
    for field in required_fields:
        assert field in content, f"notify payload missing field: {field}"


# ---------------------------------------------------------------------------
# REQ-W15: BOSS_NOTIFY not set → silent skip
# ---------------------------------------------------------------------------

def test_W15_notify_skips_silently_when_unset():
    """REQ-W15: notify must exit cleanly when BOSS_NOTIFY not set."""
    candidates = [
        REPO / "scripts" / "notify.py",
        REPO / "scripts" / "notify.sh",
        REPO / "hooks" / "notify.sh",
        REPO / "hooks" / "notify.ps1",
    ]
    script = next((p for p in candidates if p.exists()), None)
    if script is None:
        pytest.skip("notify script not yet created")
    content = script.read_text()
    # Must have early-exit guard when BOSS_NOTIFY is empty/unset
    has_guard = ("BOSS_NOTIFY" in content and
                 ("exit" in content or "return" in content or "sys.exit" in content))
    assert has_guard, "notify must have early-exit guard when BOSS_NOTIFY unset"


# ---------------------------------------------------------------------------
# REQ-W16: /run skill file exists
# ---------------------------------------------------------------------------

def test_W16_run_skill_exists():
    """REQ-W16: /run skill must exist at ~/.claude/skills/run/SKILL.md."""
    skill = SKILLS_GLOBAL / "run" / "SKILL.md"
    assert skill.exists(), f"/run skill not found at {skill}"


# ---------------------------------------------------------------------------
# REQ-W17: /run executes full pipeline in order
# ---------------------------------------------------------------------------

def test_W17_run_skill_defines_full_pipeline():
    """REQ-W17: /run SKILL.md must define research→spec→testplan→TDD→code→verify→certify→commit→push→PR."""
    skill = SKILLS_GLOBAL / "run" / "SKILL.md"
    if not skill.exists():
        pytest.skip("/run skill not yet created")
    content = skill.read_text()
    required_phases = ["research", "spec", "testplan", "verify", "certify", "commit", "push"]
    for phase in required_phases:
        assert phase.lower() in content.lower(), f"/run skill missing phase: {phase}"


# ---------------------------------------------------------------------------
# REQ-W18: /run is single entry point — one command
# ---------------------------------------------------------------------------

def test_W18_run_skill_is_single_command():
    """REQ-W18: /run SKILL.md must describe single command invocation."""
    skill = SKILLS_GLOBAL / "run" / "SKILL.md"
    if not skill.exists():
        pytest.skip("/run skill not yet created")
    content = skill.read_text()
    assert "/run" in content, "/run skill must document /run as the entry command"


# ---------------------------------------------------------------------------
# REQ-W19: /run stops only for design changes, business decisions, blockers
# ---------------------------------------------------------------------------

def test_W19_run_skill_defines_stop_conditions():
    """REQ-W19: /run must document exactly when to stop for CEO input."""
    skill = SKILLS_GLOBAL / "run" / "SKILL.md"
    if not skill.exists():
        pytest.skip("/run skill not yet created")
    content = skill.read_text()
    # Must mention design or business as stop conditions
    has_stop_conditions = ("design" in content.lower() and "business" in content.lower())
    assert has_stop_conditions, "/run skill must define design/business stop conditions"


# ---------------------------------------------------------------------------
# REQ-W20: /run resumes from .boss/run-plan.md if interrupted
# ---------------------------------------------------------------------------

def test_W20_run_skill_supports_resume():
    """REQ-W20: /run must read .boss/run-plan.md to resume from last completed phase."""
    skill = SKILLS_GLOBAL / "run" / "SKILL.md"
    if not skill.exists():
        pytest.skip("/run skill not yet created")
    content = skill.read_text()
    assert "run-plan.md" in content, "/run must reference .boss/run-plan.md for resume"


# ---------------------------------------------------------------------------
# REQ-W21: CI merge gate checks certification.json certified: true
# ---------------------------------------------------------------------------

def test_W21_ci_templates_have_certification_gate():
    """REQ-W21: all CI templates must check .boss/certification.json certified: true."""
    yaml_files = list(CI_TEMPLATES.glob("*.yml"))
    assert len(yaml_files) > 0, f"No CI templates found in {CI_TEMPLATES}"
    for yml in yaml_files:
        content = yml.read_text()
        assert "certification" in content.lower(), \
            f"{yml.name}: missing certification gate step"


# ---------------------------------------------------------------------------
# REQ-W22: All 5 CI templates updated with certification gate
# ---------------------------------------------------------------------------

def test_W22_five_ci_templates_exist():
    """REQ-W22: must have 5 CI templates (python, node, go, rust, playwright)."""
    yaml_files = list(CI_TEMPLATES.glob("*.yml"))
    names = {f.stem for f in yaml_files}
    required = {"python", "node", "go", "rust", "playwright"}
    missing = required - names
    assert not missing, f"CI templates missing: {missing}"


def test_W22_all_five_have_cert_gate():
    """REQ-W22: all 5 CI templates must have certification gate."""
    required = ["python.yml", "node.yml", "go.yml", "rust.yml", "playwright.yml"]
    for name in required:
        path = CI_TEMPLATES / name
        assert path.exists(), f"CI template missing: {name}"
        content = path.read_text()
        assert "certification" in content.lower(), \
            f"{name}: missing certification gate"


# ---------------------------------------------------------------------------
# REQ-W23: hooks/pre-push.ps1 exists
# ---------------------------------------------------------------------------

def test_W23_pre_push_ps1_exists():
    """REQ-W23: hooks/pre-push.ps1 must exist for Windows pre-push gate."""
    pre_push = HOOKS / "pre-push.ps1"
    assert pre_push.exists(), f"Windows pre-push gate missing: {pre_push}"


def test_W23_pre_push_ps1_blocks_on_test_failure():
    """REQ-W23: pre-push.ps1 must run tests and block push on failure."""
    pre_push = HOOKS / "pre-push.ps1"
    if not pre_push.exists():
        pytest.skip("pre-push.ps1 not yet created")
    content = pre_push.read_text()
    assert "pytest" in content or "test" in content.lower(), \
        "pre-push.ps1 must run tests"
    assert "exit 1" in content or "Exit 1" in content or "exit(1)" in content, \
        "pre-push.ps1 must exit 1 on failure to block push"


# ---------------------------------------------------------------------------
# REQ-W24: .boss/schemas/spec.schema.json exists and validates spec.md format
# ---------------------------------------------------------------------------

def test_W24_spec_schema_exists():
    """REQ-W24: .boss/schemas/spec.schema.json must exist."""
    schema = SCHEMAS / "spec.schema.json"
    assert schema.exists(), f"spec schema missing: {schema}"


def test_W24_spec_schema_is_valid_json():
    """REQ-W24: spec.schema.json must be valid JSON."""
    schema = SCHEMAS / "spec.schema.json"
    if not schema.exists():
        pytest.skip("spec.schema.json not yet created")
    data = json.loads(schema.read_text())
    assert "$schema" in data or "type" in data or "properties" in data, \
        "spec.schema.json must be a valid JSON schema"


def test_W24_spec_schema_has_required_sections():
    """REQ-W24: spec schema must define required sections (title, acceptance_criteria)."""
    schema = SCHEMAS / "spec.schema.json"
    if not schema.exists():
        pytest.skip("spec.schema.json not yet created")
    content = schema.read_text()
    assert "title" in content, "spec schema must require title field"
    assert "acceptance_criteria" in content or "acceptance" in content, \
        "spec schema must require acceptance_criteria"


# ---------------------------------------------------------------------------
# REQ-W25: install.ps1 generates hook command without PS & call operator
# ---------------------------------------------------------------------------

def test_W25_install_ps1_generates_no_ampersand_command():
    """REQ-W25: install.ps1 must generate hook command without PS & call operator."""
    install = REPO / "install.ps1"
    assert install.exists(), "install.ps1 not found"
    content = install.read_text()
    # The generated command string for settings.json must not use & operator
    # Look for the string that gets written to settings.json
    # Bad: `& "C:\...\powershell.exe" -File "..."`
    # Good: `powershell -ExecutionPolicy Bypass -File "..."`
    bad_pattern = r'&\s+".*powershell'
    matches = re.findall(bad_pattern, content)
    assert not matches, \
        f"install.ps1 generates & call operator in hook command: {matches}. Use 'powershell -ExecutionPolicy Bypass -File' instead"


def test_W25_install_ps1_uses_bypass_format():
    """REQ-W25: install.ps1 generated command must use powershell -ExecutionPolicy Bypass format."""
    install = REPO / "install.ps1"
    assert install.exists(), "install.ps1 not found"
    content = install.read_text()
    assert "ExecutionPolicy Bypass" in content, \
        "install.ps1 must generate hook command with -ExecutionPolicy Bypass"


# ---------------------------------------------------------------------------
# REQ-W26: install.sh + install.ps1 both installed as hooks in .github/workflows
# ---------------------------------------------------------------------------

def test_W26_github_workflows_exist():
    """REQ-W26: .github/workflows/ must contain CI for install scripts."""
    workflows = REPO / ".github" / "workflows"
    assert workflows.exists(), f".github/workflows not found at {workflows}"
    yamls = list(workflows.glob("*.yml"))
    assert len(yamls) > 0, "No workflow YAML files found"


def test_W26_ci_tests_install_sh():
    """REQ-W26: CI workflow must test install.sh."""
    workflows = REPO / ".github" / "workflows"
    if not workflows.exists():
        pytest.skip(".github/workflows not yet created")
    content = " ".join(p.read_text() for p in workflows.glob("*.yml"))
    assert "install.sh" in content, "No CI workflow tests install.sh"


def test_W26_ci_tests_install_ps1():
    """REQ-W26: CI workflow must test install.ps1."""
    workflows = REPO / ".github" / "workflows"
    if not workflows.exists():
        pytest.skip(".github/workflows not yet created")
    content = " ".join(p.read_text() for p in workflows.glob("*.yml"))
    assert "install.ps1" in content, "No CI workflow tests install.ps1"


# ---------------------------------------------------------------------------
# REQ-W17 (extended): /run skill must have concrete tool instructions
# ---------------------------------------------------------------------------

def test_W17_run_skill_has_concrete_tool_instructions():
    """REQ-W17: /run SKILL.md must reference specific Claude Code tools, not just documentation."""
    skill = SKILLS_GLOBAL / "run" / "SKILL.md"
    if not skill.exists():
        pytest.skip("/run skill not yet created")
    content = skill.read_text()
    concrete_tools = ["Glob", "Grep", "Write", "Read", "Agent", "Bash"]
    found = [t for t in concrete_tools if t in content]
    assert len(found) >= 4, \
        f"/run skill must reference at least 4 specific tools for autonomous execution. Found {len(found)}: {found}"


# ---------------------------------------------------------------------------
# REQ-W18 (extended): headless launcher exists so CEO runs one command
# ---------------------------------------------------------------------------

def test_W18_headless_launcher_exists():
    """REQ-W18: boss-run.ps1 or boss-run.sh must exist as CEO's single command."""
    ps1 = REPO / "boss-run.ps1"
    sh = REPO / "boss-run.sh"
    assert ps1.exists() or sh.exists(), \
        f"No headless launcher found. Need boss-run.ps1 or boss-run.sh"


def test_W18_headless_launcher_calls_claude():
    """REQ-W18: launcher must invoke claude CLI non-interactively."""
    ps1 = REPO / "boss-run.ps1"
    sh = REPO / "boss-run.sh"
    launcher = ps1 if ps1.exists() else (sh if sh.exists() else None)
    if not launcher:
        pytest.skip("headless launcher not yet created")
    content = launcher.read_text()
    assert "claude" in content.lower(), "launcher must invoke claude CLI"


def test_W18_headless_launcher_passes_run_skill():
    """REQ-W18: launcher must invoke /run skill."""
    ps1 = REPO / "boss-run.ps1"
    sh = REPO / "boss-run.sh"
    launcher = ps1 if ps1.exists() else (sh if sh.exists() else None)
    if not launcher:
        pytest.skip("headless launcher not yet created")
    content = launcher.read_text()
    assert "/run" in content, "launcher must pass /run to claude"


# ---------------------------------------------------------------------------
# REQ-W13 (extended): CI templates actually call notify.py
# ---------------------------------------------------------------------------

def test_W13_all_ci_templates_call_notify():
    """REQ-W13: all 5 CI templates must call notify.py so CEO gets notified."""
    required = ["python.yml", "node.yml", "go.yml", "rust.yml", "playwright.yml"]
    for name in required:
        path = CI_TEMPLATES / name
        assert path.exists(), f"CI template missing: {name}"
        content = path.read_text()
        assert "notify" in content.lower(), \
            f"{name}: does not call notify.py — CEO will never be notified of CI result"
