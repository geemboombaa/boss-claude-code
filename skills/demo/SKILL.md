# /demo — BOSS Demo Generator (Phase 1.5)

You are generating demo artifacts from `.boss/spec.md` BEFORE any source code is written.

The CEO must see and approve these artifacts before you write a single source file.

## What You Must Produce

Read `.boss/spec.md`. Based on the project type, generate the appropriate demo artifact in `.boss/demo-artifacts/`:

### UI / Frontend / Full-stack
Write `.boss/demo-artifacts/wireframe.md`:
```markdown
# Wireframe: [Feature Name]

## Screen: [screen name]
[ASCII art or structured layout showing UI elements, labels, interactions]

## User Flow
1. [Step 1]
2. [Step 2]
...

## Edge Cases Shown
- [empty state, error state, loading state, etc.]
```

### API / Backend
Write `.boss/demo-artifacts/api-contract.md`:
```markdown
# API Contract: [Feature Name]

## Endpoints

### POST /path/to/endpoint
Request:
```json
{"field": "value"}
```
Response 200:
```json
{"result": "value"}
```
Response 4xx:
```json
{"error": "message", "code": "ERROR_CODE"}
```

## Validation Rules
- [rule 1]
- [rule 2]
```

### Service / Library / CLI
Write `.boss/demo-artifacts/sequence.md`:
```markdown
# Sequence Diagram: [Feature Name]

[Component A] -> [Component B]: [action]
[Component B] -> [Component A]: [response]

## Invariants
- [invariant 1]
- [invariant 2]

## Data Flow
[describe how data moves through the system]
```

## Rules

- **No source code.** Demo artifacts are design documents only.
- Be specific enough that the CEO can confirm this matches their intent.
- Include edge cases, error states, and boundary conditions.
- If unclear: put your assumptions explicitly and ask CEO to confirm.

## After Writing Artifacts

Output to CEO:
```
Demo artifacts written to .boss/demo-artifacts/.

Please review and run /signoff to approve, or reply with changes needed.

[paste key parts of the wireframe/contract/sequence inline here]
```

**Do not write any source code until the CEO runs /signoff.**
