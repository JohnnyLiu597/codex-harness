# Workflow Graph Contract

Use this contract for a Codex workflow with multiple delegated nodes, stages,
joins, retries, approvals, or resume points. It shapes native Codex work; it is
not a second scheduler or agent runtime.

## Admission

Keep a single execution path unless a graph earns its coordination cost through
one or more of:

- independent parallel branches
- context isolation from noisy intermediate work
- specialized tools, permissions, or instructions
- independent maker-checker separation
- durable recovery across interruption or partial failure

State the expected gain and the cost budget before adding nodes. Use an eval or
ablation record when the benefit is uncertain or the workflow will recur.

## Topologies

| Shape | Use when | Required control |
|---|---|---|
| Serial pipeline | one result is a real dependency of the next | typed handoff and per-stage check |
| Fan-out/fan-in | branches are independent | join policy, deduplication, missing-branch rule |
| Supervisor-workers | decomposition must adapt during execution | spawn budget, ownership, final integrator |
| Evaluator-optimizer | output can improve against a measurable criterion | fresh checker, retry cap, stop condition |

Do not parallelize dependent work merely to increase agent count.

## Node Contract

Each node defines:

- node ID, owner, objective, and non-goals
- dependencies and input artifact hashes
- read/write scope and isolation
- expected output schema and evidence path
- time, token, tool, and retry budget
- checker, acceptance rule, and stop reason

Nodes return compact evidence and conclusions. Keep raw tool output and noisy
intermediate context in the worker thread or ephemeral artifacts.

## Edge Contract

Each edge defines its source, destination, transition condition, data passed,
failure route, and approval boundary. Use deterministic code for validation,
format checks, budgets, path policy, state transitions, and completion gates.
Use model judgment inside bounded nodes where interpretation is the work.

## Checkpoint And Resume

Record run ID, attempt ID, accepted nodes, pending nodes, output hashes, last
verified commit, and next transition. On retry, reuse accepted sibling outputs
when their inputs and acceptance evidence still match. Do not rerun successful
branches only because another branch failed.

A resumed node may execute from its beginning. Put irreversible side effects
after approval, make them idempotent, or protect them with a stable deduplication
key.

## Governance

The task graph may adapt within declared budgets. The role and permission graph
must change slowly: tool access, protected paths, commit/publish rights, and
approval requirements stay explicit and auditable.

Completion requires a reality anchor such as a real test, source retrieval,
runtime observation, external status, or user approval. Model agreement alone
does not close the workflow.
