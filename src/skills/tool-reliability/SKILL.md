---
name: tool-reliability
description: Diagnose and recover from Codex tool failures, timeouts, malformed inputs, unexpected output, repeated calls, unavailable dependencies, or permission and environment blockers. Use when a tool path must be made reliable without hiding the original failure.
---

# Tool Reliability

Preserve evidence, change one assumption at a time, and keep recovery bounded.

## Failure Workflow

1. Capture the tool name, operation, exit or error class, elapsed time, and the
   minimum safe context needed to reproduce it. Redact secrets and private
   payload values.
2. Classify the failure:
   - malformed input or schema mismatch
   - unavailable command, file, service, or dependency
   - permission, login, quota, or policy blocker
   - timeout, transient transport, or rate limit
   - output truncation or parsing failure
   - tool defect or unsupported operation
   - task assumption or context error
3. Check the local contract before claiming a capability is unavailable:
   `Get-Command`, configured paths, tool help, project docs, and current runtime
   state.
4. Retry only when the class is retryable. Keep the retry count bounded and
   change one variable at a time so the result is diagnosable.
5. Validate the recovered output semantically, not only by process exit code.
6. Rerun the original path after a fix. If it still fails, use a genuinely
   different route or report the blocker.

## Loop Guard

Treat repeated identical tool calls with no new evidence as a loop. Stop,
compare the last observations, identify the unchanged assumption, and either
alter the approach or escalate. Do not spend the remaining budget repeating an
operation that has already failed deterministically.

## Durable Evidence

When a failure affects the task, repeats, or reveals a harness gap, record it
with the nearest project script or the global equivalent:

```powershell
.\scripts\new-tool-failure.ps1
```

Route the result to one of: docs, test, eval, skill, rule, script, component
change, environment fix, or user action. Do not automatically mutate the
harness from a single failure.

## Safety

- Do not bypass approvals, sandboxing, or credential boundaries to make a tool
  appear successful.
- Do not persist raw auth data, cookies, tokens, browser state, transcripts, or
  full tool payloads in failure artifacts.
- Do not replace a deterministic parser or API with an LLM unless the remaining
  ambiguity actually requires semantic reasoning.
- Do not claim success when the required process or session is still running.

## Output

Return the observed failure, classification, attempts, changed assumption,
reproduction result, evidence path, and any remaining blocker.
