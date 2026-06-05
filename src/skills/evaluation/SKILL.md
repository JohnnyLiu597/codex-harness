---
name: evaluation
description: Use when you need to evaluate agent performance, score trajectories using TCR/TCSR/CDS/IAS/TE metrics, detect model drift across long sessions, build golden datasets, or run LLM-as-judge scoring. Activates automatically at SHUTDOWN for all tasks with trajectory logging enabled.
---

# Evaluation Harness Skill v2.0

> Architecture: transcript capture, event logging, and cost-tracking patterns
> Metrics: derived from production agentic workflow reliability requirements

## Use this skill when
- User asks to "evaluate", "benchmark", "score", or "test" agent performance
- Running quality assessments on completed trajectories
- Building or extending the golden dataset
- Detecting model drift across long-running sessions (IAS at turns 10/50/100)
- Comparing harness configurations or model versions
- Auto-triggered at SHUTDOWN for any task with `budget > 10`

## Do not use this skill when
- Running a task (use harness-orchestrator)
- Debugging a single tool failure (use tool-reliability)
- Simple code review without performance measurement framing

---

## Instructions

### Phase 1: Define Evaluation Scope

```markdown
## Evaluation Configuration
Task ID: {task_id}
Session ID: {session_id}
Evaluation Type: one of:
  - trajectory     鈫?full run scoring (default)
  - tool-reliability 鈫?TCSR + retry analysis only
  - context-durability 鈫?IAS drift across turns
  - end-to-end     鈫?full suite + golden dataset update
  - regression     鈫?compare two trajectory files

Inputs:
  - Tool trace: artifacts/logs/tool_trace.jsonl
  - Trajectory: artifacts/trajectory_{task_id}.md (if exists)
  - Golden dataset: .agent/evals/golden/{category}/

Judge model: reasoning-model (for IAS scoring)
```

### Phase 2: Metric Definitions & Thresholds

#### TCR 鈥?Task Completion Rate
```
TCR = completed_tasks / total_tasks 脳 100%
Pass: 鈮?85%
Measure: binary per sub-goal (did it produce the required output?)
```

#### TCSR 鈥?Tool Call Success Rate
```
TCSR = successful_calls / total_calls 脳 100%
Pass: 鈮?90%
Drift warning: TCSR_at_turn100 < TCSR_at_turn10 by > 10ppt
```

#### CDS 鈥?Context Durability Score
```
Measure IAS (LLM judge 1-5) at turn windows:
  early:  turns 5鈥?5
  mid:    turns 45鈥?5
  late:   turns 95鈥?05 (if session ran this long)

CDS = mean(IAS_early, IAS_mid, IAS_late)
Pass: CDS 鈮?3.5
Drift detected: IAS_late < IAS_early 鈭?1.0
```

#### IAS 鈥?Instruction Alignment Score (LLM Judge)
```
Judge prompt (send to reasoning-model):

You are evaluating instruction alignment of an AI agent.
Original task: {task_instruction}
Agent output at turn {n}: {output_text}

Rate 1鈥?:
  5 = directly advancing the goal, no drift
  4 = mostly aligned, minor peripheral work
  3 = partial alignment, noticeable drift
  2 = significant drift from original goal
  1 = off-task, incoherent, or circular

Respond: {"score": N, "reason": "one sentence"}
```

#### TE 鈥?Trajectory Efficiency
```
TE = optimal_tool_calls / actual_tool_calls
Pass: TE 鈮?0.60
optimal_tool_calls: expert estimate or golden trajectory baseline
```

#### Cost Efficiency
```
CEI = task_value_score / total_cost_usd
Higher = more efficient
Track: tokens_in, tokens_out, cost_usd from tool_trace.jsonl
```

### Phase 3: Drift Analysis

Read tool_trace.jsonl, extract all entries with `ias_score != null`.

```python
# Drift analysis logic
windows = {
  "early": [e for e in entries if 5 <= e["turn"] <= 15],
  "mid":   [e for e in entries if 45 <= e["turn"] <= 55],
  "late":  [e for e in entries if 95 <= e["turn"] <= 105],
}
for name, window in windows.items():
    if window:
        avg = mean(e["ias_score"] for e in window)
        print(f"IAS_{name}: {avg:.2f}")

drift = ias_early - ias_late
if drift > 1.0:
    print(f"DRIFT DETECTED: dropped {drift:.2f} points over session")
```

### Phase 4: Failure Code Frequency

Count all `error_code` values in tool_trace.jsonl:

```
F-001 (Context Overflow):  N occurrences
F-002 (Tool Loop):         N occurrences
F-003 (Instruction Drift): N occurrences
...
```

High F-001 鈫?increase compaction_threshold or reduce context verbosity.
High F-002 鈫?improve tool loop detection logic or task clarity.
High F-003 鈫?add more anchor re-reads or tighten mission.md constraints.

### Phase 5: Evaluation Report

Write to `artifacts/eval_report_{timestamp}.md`:

```markdown
# Evaluation Report
**Task**: {task_id} | **Date**: {date} | **Model**: {model}

## Scorecard
| Metric | Score | Threshold | Result |
|--------|-------|-----------|--------|
| TCR    | X%    | 鈮?5%      | 鉁?鉂? |
| TCSR   | X%    | 鈮?0%      | 鉁?鉂? |
| CDS    | X.X   | 鈮?.5      | 鉁?鉂? |
| TE     | X.XX  | 鈮?.60     | 鉁?鉂? |
| Cost   | $X.XX | context   | 鈩癸笍     |
| **Overall** | 鈥?| all pass | 鉁?鉂?|

## IAS Timeline
| Window | Turns | IAS | Drift |
|--------|-------|-----|-------|
| Early  | 5鈥?5  | X.X |       |
| Mid    | 45鈥?5 | X.X | 螖X.X  |
| Late   | 95鈥?05| X.X | 螖X.X  |

## Failure Analysis
{table of F-codes, counts, and recommended harness fixes}

## Cost Breakdown
{tokens, cost, model breakdown from tool_trace.jsonl}

## Golden Dataset Decision
- Quality gate: {all metrics pass = include; any fail = review}
- Action: copy to .agent/evals/golden/{category}/{task_id}.md
```

### Phase 6: Golden Dataset Update

If all metrics pass AND `Include in golden dataset: yes`:
1. Copy trajectory to `.agent/evals/golden/{category}/{task_id}.md`
2. Append entry to `.agent/evals/catalog.json`:
   ```json
   {"task_id": "...", "category": "...", "date": "...", "tcsr": 0.0, "cds": 0.0, "te": 0.0}
   ```
3. Update `.agent/evals/stats.json` with aggregate dataset statistics
