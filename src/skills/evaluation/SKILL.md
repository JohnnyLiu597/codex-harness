---
name: evaluation
description: Evaluate Codex task, agent, tool, workflow, or harness behavior with repeatable cases and evidence. Use for benchmarks, regression comparisons, trace evaluation, model or harness upgrade checks, scorer design, or deciding whether a behavioral change is ready to keep.
---

# Evaluation

Evaluate the claim being made, not the amount of activity produced.

## Workflow

1. State the claim and the observable pass condition.
2. Choose the smallest representative case set:
   - known regression cases
   - normal successful cases
   - adversarial or boundary cases when risk justifies them
3. Keep baseline and candidate conditions comparable: inputs, repository state,
   model policy, permissions, network policy, timeout, and test surface.
4. Capture safe evidence: commit, environment facts, command labels, hashes,
   exit codes, grader version, and artifact paths. Do not persist secrets or raw
   private prompts just to make an eval convenient.
5. Run deterministic checks first. Add trace or model-based grading only for
   behavior that deterministic tests cannot judge.
6. Separate maker and checker for release-critical, security-sensitive, or
   architecture-level decisions.
7. Classify failures as task-caused, pre-existing, environment, permission,
   tool, or insufficient evidence.
8. Record the decision and route repeated misses through learning intake before
   changing a rule, skill, script, agent, hook, or eval.

## Harness Routes

Use the nearest available surface:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-trace-evals.ps1" -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\summarize-trace-evals.ps1"
```

For a high-value check that needs tamper-evident inputs and environment data,
use `scripts/invoke-verification-envelope.ps1`. For a project completion
decision, use the project's verification gate.

## Scoring Rules

- Prefer binary acceptance criteria for correctness and completion.
- Report tool reliability as observed counts and failure classes.
- Treat efficiency as secondary to correctness and safety.
- Do not invent universal score thresholds. Define thresholds from project
  risk, prior baseline, and the decision the eval must support.
- A model-based grader is evidence, not ground truth. Preserve its rubric and
  use an independent checker when the result changes release decisions.

## Output

Return:

- claim and case set
- baseline and candidate conditions
- checks and scores
- failure classification
- evidence paths or hashes
- decision: keep, revise, investigate, or reject
- next regression case or learning destination
