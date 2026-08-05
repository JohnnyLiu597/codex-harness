# Testing

Testing uses a risk-tiered release gate for this harness source project.

## Release Verification

Run the lowest sufficient gate before committing or pushing:

```powershell
.\deploy\verify-release.ps1 -Level Fast
```

| Level | What it runs | Use when | Skip when |
|---|---|---|---|
| Fast | `git diff --check`, `git diff --cached --check`, and package public-readiness | docs, templates, skills, low-risk scripts, wording-only policy changes | runtime install, sync behavior, hooks, agents, workflow scripts, or eval behavior changed |
| Standard | Fast plus an isolated source-to-staging sync and one global static/runtime-health pass; optionally install only with explicit `-InstallRuntime` | runtime payload changed and staging compatibility matters | docs-only changes or changes that clearly do not affect runtime payload |
| Full | Standard plus isolated staging `CODEX_HOME`, one global static/runtime-health pass, one deterministic eval pass, and a sanitized release manifest; real runtime install remains opt-in | hooks, agents, workflow-control scripts, evals, sync scripts, public-readiness rules, verification envelopes, job-state/learning/component workflow, or release-critical changes | routine docs/skill/template edits already covered by Fast or Standard |

Do not run deterministic harness evals as a default closure step for every
GitHub push. They are regression evidence for high-risk harness behavior, not a
tax on every typo fix.

This documentation closure corresponds to the workflow-core P0/P1/P2 upgrade
and should be treated as `Full` because it documents behavior that now spans
hook lifecycle guardrails, sub-agent closure, verification plumbing, and source
publication boundaries.

## Package Verification

Run this before committing changes:

```powershell
.\deploy\verify-package.ps1
```

The package check verifies:

- Required project files exist.
- Required runtime payload files exist in `src/`.
- The weekly automation template has portable placeholders, worktree isolation,
  and no fixed model, reasoning effort, or machine-local path.
- Forbidden runtime files are absent from `src/`.
- PowerShell scripts parse.
- JSON manifests parse.
- Every published skill includes a loadable `SKILL.md` that starts with YAML
  frontmatter in UTF-8 without BOM, and its `name` matches the skill folder.
- Runtime/source sync boundary fixtures prove that secrets, state databases,
  logs, sessions, plugins, caches, browser state, backup files, archived
  payloads, nested sandbox/TEMP state, and `.codex-private` skills do not cross
  either sync direction. App-owned automation state is preserved.
- Standalone custom-agent files include portable `name`, `description`, and
  `developer_instructions` fields and omit reusable model/reasoning pins.
- Codex CLI entrypoints probe candidate executables with `--version`, and the
  runtime verifier tests fallback from a failing candidate before running
  `codex features list` to detect config-schema drift.
- Every published PowerShell script under `deploy/` and `src/`, including
  project-scaffold templates and skill scripts, is parsed.

## Workflow-Core Regression Set

Use this set when the Codex workflow core changed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\test-codex-workflow-core.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-verification-gate.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-verification-envelope.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-trace-evals-v3.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-project-harness-optimizer.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-weekly-harness-learning.ps1"
```

These checks cover causally paired hook verification, session-bound weekly
restrictions, the exact read-tool allowlist, external write-tool denial,
registered-only and oversized-input cleanup, verification gate process exits,
verification envelope required evidence and stale-input detection, trace eval
grading/timeout/cleanup, workflow-core invariants, and optimizer routing.

The workflow-core check also rejects hook fields that the current Codex CLI
does not support for that lifecycle event. Static JSON validity is not enough.

## Runtime Verification

After a manual sync outside the release orchestrator, run both owners:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
```

`Full -InstallRuntime` already runs deterministic evals against staging, so its
install phase reruns only global runtime health and the hook wiring canary.

For a broader health snapshot:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\harness-health.ps1" -SkipEvals
```

The known accepted warning is `provider-token-location`, caused by the current
local custom provider token configuration in runtime `config.toml`.

## Verification Matrix

| Surface | Minimum check | Escalate to |
|---|---|---|
| Docs-only wording or structure | `.\deploy\verify-release.ps1 -Level Fast` | Standard if runtime sync wording changed |
| Runtime/source flow, publication boundary, or package exclusions | `.\deploy\verify-release.ps1 -Level Full` | plus manual package review when preparing publication |
| Hooks, adaptive sub-agent guardrails, or workflow entrypoints | workflow-core regression set plus real CLI config probe | Full release gate |
| Verification envelope or gate scripts | `test-verification-gate.ps1` and `test-verification-envelope.ps1` | Full staging release gate |
| Trace/tool-eval closure or learning intake routing | `run-harness-evals.ps1` | Full release gate when shared harness behavior changed |
| Context budget, job-state, or component registry policy | targeted script run plus package verification | Full release gate if the shared harness contract changed |

For hook or custom-agent contract changes, add one bounded real Codex CLI
config probe and hook wiring canary after deterministic checks. This can prove
the installed wrapper/router and definition hash, but hook trust remains a
manual `/hooks` review when the definition changes. Treat provider, plugin, or
optional MCP warnings separately from task-caused harness failures.
