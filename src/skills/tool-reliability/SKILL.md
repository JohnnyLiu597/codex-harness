---
name: tool-reliability
description: Use when a Codex tool call fails, times out, returns unexpected output, triggers a tool loop, exceeds concurrency rules, or approaches the tool budget limit.
---

# Tool Reliability Skill v2.0

> Architecture: tool orchestration, typed error handling, retry limits, and loop detection

## Use this skill when
- Any tool call returns an error or unexpected output
- Detecting a tool loop (same tool + same input 鈮?3 times)
- Tool budget soft limit (50) or warning threshold (80) reached
- Concurrency violation detected (serial tool running during concurrent batch)
- `max_output_tokens` error 鈫?also triggers context-guard
- Need to diagnose why a sub-agent worker failed

## Do not use this skill when
- Tools are running normally
- Error is obviously a user input issue (just fix the input)

---

## Instructions

### Concurrency Execution Model

Use this batching model:

```
BATCH FORMATION RULES:
  1. Collect all tool uses from current API response
  2. Partition by concurrency tier:
     Tier-1 (safe):   read_file, glob, grep, web_search, web_fetch
     Tier-2 (serial): write_file, edit_file, run_shell, spawn_agent
     Tier-3 (gated):  delete_file, publish, deploy

  3. Execution order:
     a. All Tier-1 tools in current batch 鈫?run in PARALLEL
     b. Wait for ALL Tier-1 to complete
     c. Tier-2 tools 鈫?run ONE AT A TIME (serial)
     d. Tier-3 tools 鈫?PAUSE_FOR_HUMAN before each

  4. Context modifiers: queue all, apply SERIALLY after batch completes
     (never apply contextModifiers concurrently 鈥?order matters)

  5. Sibling abort: each tool has independent abort controller
     One Tier-1 failure 鈫?does NOT cancel other Tier-1 siblings
     Coordinator: cancel worker only if worker produces FATAL error
```
### Error Classification Tree

```
Tool call failed?
鈹?鈹溾攢鈹€ HTTP 429 / rate_limit_exceeded?
鈹?  鈫?RETRYABLE: exponential backoff (1s, 2s, 4s, 8s, 16s, max 5 retries)
鈹?鈹溾攢鈹€ HTTP 408 / timeout?
鈹?  鈫?RETRYABLE: linear backoff (2s, 4s, 6s, max 3 retries)
鈹?鈹溾攢鈹€ HTTP 503 / transient_network?
鈹?  鈫?RETRYABLE: fixed 2s, max 3 retries
鈹?鈹溾攢鈹€ max_output_tokens error?
鈹?  鈫?RETRYABLE via compact: trigger context-guard REACTIVE_COMPACT
鈹?    then retry (max 3 compact+retry cycles 鈫?F-008 if still failing)
鈹?鈹溾攢鈹€ HTTP 403 / permission_denied?
鈹?  鈫?FATAL: HITL pause. "Tool {name} returned permission denied.
鈹?    I cannot proceed without authorization. Please check permissions."
鈹?鈹溾攢鈹€ HTTP 404 / resource_not_found?
鈹?  鈫?SELF-FIX: Verify assumptions. Does the resource exist?
鈹?    Correct path/ID and retry once.
鈹?    If still 404: FATAL 鈫?HITL pause
鈹?鈹溾攢鈹€ Pydantic / schema validation error?
鈹?  鈫?SELF-FIX: Re-read tool input schema. Correct inputs. Retry once.
鈹?    If retry fails: FATAL
鈹?鈹溾攢鈹€ Tool budget exceeded (> 100 calls)?
鈹?  鈫?FATAL (F-005): HITL pause with progress report
鈹?鈹斺攢鈹€ Unknown / unexpected error?
    鈫?Log full error. Retry once with identical inputs.
      If retry fails: FATAL 鈫?HITL pause with full error context
```

### Retry Policy (reference)

```yaml
retry_policies:
  rate_limit:
    max_retries: 5
    strategy: exponential
    base_delay_s: 1.0
    max_delay_s: 30.0

  timeout:
    max_retries: 3
    strategy: linear
    base_delay_s: 2.0

  transient_network:
    max_retries: 3
    strategy: fixed
    delay_s: 2.0

  max_output_tokens:
    max_retries: 3
    strategy: compact_then_retry
    compact_skill: context-guard

  schema_validation:
    max_retries: 1
    strategy: self_fix
    action: "re-read input schema, correct inputs"
```

### Tool Loop Detection & Recovery

A tool loop = calling the same tool with the same (or structurally identical) inputs 3+ times.

**Detection algorithm:**
```
1. For each new tool call, compute input_hash = hash(tool_name + sorted(inputs))
2. Scan last 10 entries in tool_trace.jsonl
3. Count: how many times does this input_hash appear?
4. If count 鈮?3: TOOL_LOOP_DETECTED
```

**Recovery protocol (F-002):**
```
IMMEDIATE: Stop all pending tool calls
LOG: {"action": "TOOL_LOOP", "tool": name, "input_hash": hash, "count": n, "turn": t}

DIAGNOSE:
  1. Re-read original task: "What am I trying to achieve overall?"
  2. Re-read last 5 tool calls: "Why did I call this tool each time?"
  3. Identify the root cause:
     A. The tool is the wrong tool for the goal 鈫?find alternative
     B. The output is being interpreted incorrectly 鈫?parse differently
     C. The task goal is unclear 鈫?HITL for clarification
     D. A dependency is missing 鈫?resolve dependency first

RESUME:
  - If A: use different tool or approach
  - If B: extract the actual needed information from tool output
  - If C or D: HITL pause with loop diagnosis

LOG: {"action": "TOOL_LOOP_RESOLVED", "root_cause": "A|B|C|D", "resolution": "..."}
```

### Tool Budget Enforcement

```
Budget checkpoints:

At 50 calls (soft limit):
  鈫?Write checkpoint_{n}.md
  鈫?Self-review: "Am I on track? Can I complete in 鈮?50 more calls?"
  鈫?Log: BUDGET_SOFT | remaining={50}

At 80 calls (warning):
  鈫?Estimate: how many calls to completion?
  鈫?If 鈮?20: proceed with focused, efficient plan
  鈫?If > 20: HITL pause with progress + revised estimate
  鈫?Log: BUDGET_WARNING | remaining={20}

At 100 calls (hard limit 鈥?F-005):
  鈫?STOP all tool calls immediately
  鈫?Write: trajectory summary with current state
  鈫?HITL pause: "I have used 100 tool calls. Progress: [summary].
     Estimated calls to completion: [N]. Should I continue?"
  鈫?Only resume after explicit human confirmation
```

### Output Validation

After every tool call, validate before using the output:

```
read_file:    鈫?not empty, format matches expectation, encoding is valid
write_file:   鈫?exit code 0, read back to verify content was written
web_search:   鈫?results are topically relevant to the query
web_fetch:    鈫?not an error page (check status code), content is readable
run_shell:    鈫?exit code 0, stderr is empty or contains only warnings
spawn_agent:  鈫?sub-agent completed (check notifications/), output file exists
list_dir:     鈫?returns expected directory structure

On validation failure:
  鈫?classify error as above
  鈫?apply retry or self-fix policy
  鈫?if FATAL: HITL pause with validation failure details
```

### Cost-Aware Tool Selection

Cost-aware tool choice 鈥?prefer cheaper tools when equivalent:

```
For information retrieval:
  1. read_file (free) > web_fetch (costs tokens) > web_search (most expensive)
  2. grep/glob (fast, cheap) before read_file for discovery tasks
  3. Sub-agents: use fast-model for routine tasks, not reasoning-model

For writing:
  1. edit_file (targeted, cheap) > write_file (full rewrite, expensive)
  2. Batch related edits into single write_file call when possible
```
