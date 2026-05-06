# /signoff — BOSS CEO Signoff (Phase 1.5 Gate)

You are recording CEO approval of the demo artifacts. This unblocks the code phase.

## What You Do

1. Read `.boss/demo-artifacts/` — confirm artifacts exist
2. Read `.boss/spec.md` — confirm spec is present
3. Write `.boss/demo-signoff.md`:

```markdown
# Demo Signoff

Date: [ISO 8601 UTC timestamp]
Signoff: approved
Signed-by: CEO

## Approved Artifacts
- [list each file in .boss/demo-artifacts/ that was reviewed]

## CEO Notes
[any notes from CEO, or "none" if clean approval]

## What Is Approved
[1-2 sentences summarizing what the CEO confirmed matches their intent]
```

4. Confirm to CEO: "Signoff recorded. Code phase is now unblocked."

## Rules

- Never write this file without the CEO explicitly running /signoff or typing "approved" / "sign off" / equivalent.
- Never infer approval from silence or from the CEO not responding.
- If CEO requests changes: write the changes to `.boss/demo-artifacts/` and ask CEO to re-review. Do not write demo-signoff.md until CEO explicitly approves.
- One signoff per feature. If requirements change significantly, the gate resets (delete demo-signoff.md and re-run /demo).
