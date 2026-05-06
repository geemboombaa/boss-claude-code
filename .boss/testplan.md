# BOSS Test Plan — For Agent 2 (Verifier)

## Test Execution Order

### 1. Python unit tests (automated)
```bash
cd /path/to/boss
python -m pytest tests/ -v --tb=short --junitxml=.boss/test-results/junit.xml 2>&1 | tee .boss/test-results/stdout.txt
```
Expected: 21+ passed, ≤10 skipped (bash tests skip on Windows)

### 2. Schema existence checks
```python
import json, pathlib
schema = json.loads(pathlib.Path(".boss/schemas/certification.schema.json").read_text())
assert "$schema" in schema
assert "properties" in schema
```

### 3. File existence checks
```bash
for f in hooks/stop-gate.sh hooks/stop-gate.ps1 hooks/commit-msg.sh hooks/pre-push.sh \
          scripts/patch-settings.py install.sh install.ps1 bin/boss.js package.json LICENSE \
          skills/verify/SKILL.md skills/certify/SKILL.md \
          templates/python-backend.md templates/node-api.md templates/fullstack.md \
          templates/go-service.md templates/rust-crate.md templates/generic.md \
          ci-templates/python.yml ci-templates/node.yml ci-templates/go.yml \
          ci-templates/rust.yml ci-templates/playwright.yml; do
  test -f "$f" || echo "MISSING: $f"
done
```

### 4. Bash syntax check
```bash
bash -n hooks/stop-gate.sh && echo "PASS: stop-gate.sh syntax"
bash -n hooks/commit-msg.sh && echo "PASS: commit-msg.sh syntax"
bash -n hooks/pre-push.sh && echo "PASS: pre-push.sh syntax"
bash -n install.sh && echo "PASS: install.sh syntax"
```

### 5. JSON validity checks
```python
import json
for f in ["package.json", ".boss/schemas/certification.schema.json"]:
    json.loads(open(f).read())
    print(f"PASS: {f} is valid JSON")
```

### 6. patch-settings.py integration tests
```python
import subprocess, json, tempfile, pathlib, os

# Test: creates file
with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as t:
    path = t.name
os.unlink(path)
subprocess.run(["python", "scripts/patch-settings.py", "--settings", path, "--platform", "unix"], check=True)
data = json.loads(open(path).read())
assert "Stop" in data["hooks"]
assert "SubagentStop" in data["hooks"]
print("PASS: creates settings.json")

# Test: idempotent
subprocess.run(["python", "scripts/patch-settings.py", "--settings", path, "--platform", "unix"], check=True)
data2 = json.loads(open(path).read())
boss_entries = [h for e in data2["hooks"]["Stop"] for h in e.get("hooks", []) if "boss" in str(h).lower()]
assert len(boss_entries) == 1
print("PASS: idempotent")
```

### 7. Hook behavior tests (Unix only)
```bash
# BOSS_SKIP bypass
echo '{"session_id":"x","cwd":"/tmp","stop_hook_active":false}' | BOSS_SKIP=1 bash hooks/stop-gate.sh
echo "Exit: $? (expected 0)"

# stop_hook_active loop prevention
echo '{"session_id":"x","cwd":"/tmp","stop_hook_active":true}' | bash hooks/stop-gate.sh
echo "Exit: $? (expected 0)"
```

## Proof Artifacts Required
- .boss/test-results/stdout.txt (pytest output)
- .boss/test-results/junit.xml (pytest junit)
- Screenshot of test run (if running interactively)
