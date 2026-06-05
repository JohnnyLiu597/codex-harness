---
name: context-guard
description: Use when Codex context is getting large, the task drifts, max output errors occur, or a sub-agent needs isolated context.
---

# Context Guard Skill v2.0

> Architecture: auto-compact, reactive-compact, snip-compact, and token budgeting patterns

## Use this skill when
- Context usage > 70% (auto trigger)
- `max_output_tokens` error received (reactive trigger — highest priority)
- Turn count > 30 (scheduled trigger)
- IAS self-score ≤ 3 (drift-driven compaction)
- Spawning a sub-agent (isolation trigger)
- User or harness requests `/compact`

## Do not use this skill when
- Context < 50% and turn count < 20 and IAS ≥ 4
- Compaction was done in the last 5 turns

---

## Instructions

### Compaction Strategy Selection

```
REACTIVE_COMPACT (highest priority):
  Trigger: max_output_tokens error
  Max attempts: 3 (after 3 failures: F-008, HITL pause)
  Action: compact immediately, before retrying the failed call
  Note: this is the only strategy that interrupts mid-turn

AUTO_COMPACT (normal operation):
  Trigger: context_pct > 70
  Timing: queued, executes before next API call
  Action: full compaction with pre/post hooks

MICRO_COMPACT (mid-turn):
  Trigger: context overflow mid-tool-batch
  Action: snip oldest non-anchor messages (FIFO eviction)
  Preserve: original task, last 5 turns, critical facts

SCHEDULED_COMPACT (maintenance):
  Trigger: every 30 turns regardless of context %
  Action: full compaction + anchor verification
```

### Pre-Compact Hook (always runs before any compaction)

```
1. Emit: PRE_COMPACT | turn={n} | context={pct}% | trigger={type}
2. Write snapshot: artifacts/context_snapshot_{n}.md (full current context)
3. Log to tool_trace.jsonl: {"action": "compaction", "phase": "PRE_COMPACT", ...}
```

### Drift Detection Checklist (run before deciding compaction type)

```
[ ] Re-read original task. Does the last 3 outputs still address it directly?
[ ] Check IAS trend: is IAS declining across last 5 tool calls?
[ ] Check tool_trace.jsonl: are calls still purposeful or becoming redundant?
[ ] Are outputs growing longer but less specific?
[ ] Is the agent re-explaining context it already established?

0-1 checked → MICRO_COMPACT sufficient
2-3 checked → AUTO_COMPACT recommended
4-5 checked → DRIFT CONFIRMED → AUTO_COMPACT + IAS realignment
```

### Compaction Summary Template

```markdown
## Context Compaction — Turn {n} | Trigger: {type}
> Context before: {pct}% | Model: {model}

### ANCHOR — Original Task (never discard)
{verbatim original task instruction — copy exactly}

### Completed Steps
1. {step} → {outcome}
2. {step} → {outcome}
...

### Active Decisions (non-obvious choices to preserve)
- Decision: {what} | Rationale: {why} | Impact: {consequence if forgotten}

### Current State (exactly where we are)
{one paragraph — precise enough to resume without re-reading history}

### Critical Facts (must survive all future compactions)
| Fact | Value | Why critical |
|------|-------|-------------|
| {key} | {value} | {reason} |

### Next Action
{single next tool call or decision — be precise}
```

### Post-Compact Verification

After compaction, verify the anchor survived:
```
1. Re-read compacted context
2. Confirm original task is present verbatim
3. Confirm critical facts table is intact
4. IAS self-score: does compacted context still support aligned execution?
   If IAS < 4: compaction was lossy — add back missing facts before proceeding
5. Emit: POST_COMPACT | context_after={pct}% | anchor_verified={true|false}
```

### Sub-agent Context Isolation

When spawning a sub-agent, NEVER pass full parent context. Build a minimal context package:

```markdown
## Sub-agent Context Package for {agent_id}

### Sub-goal (the ONLY task)
{precise sub-goal — one sentence}

### Essential Facts
{only facts needed for this specific sub-goal — nothing else}
{test each fact: "would the sub-agent fail without this?" If no, exclude it}

### Tool Allowlist
{list only tools needed — workers get restricted set, not full parent tool list}

### Output Location
artifacts/sub_{agent_id}_output.{ext}

### Output Format
{exact schema/format — no ambiguity}
```

Context isolation principle: if sub-agent output can be summarized in 1-2 paragraphs before returning to parent, the context package was correct size.

### Anchor Re-Read Schedule

```
Every 10 tool calls:  re-read mission.md (mandatory)
Every 20 tool calls:  re-read original task verbatim
Every phase boundary: re-read current phase goal
After any HITL pause: re-read mission.md + original task
After compaction:     re-read compaction summary + verify alignment
```

### IAS Realignment Protocol

When IAS ≤ 3, run realignment before resuming:

```
REALIGNMENT PROTOCOL:
  Step 1: Re-read original task (verbatim)
  Step 2: State the goal in your own words
  Step 3: Review last 5 outputs — identify where drift started
  Step 4: State: "My next action must directly advance [goal] by [specific step]"
  Step 5: IAS self-score the realignment statement (should be 5)
  Step 6: Proceed only after IAS self-score = 5

  Log: REALIGNMENT | turn={n} | ias_before={x} | ias_after=5
```
