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
| Standard | Fast plus `sync-to-runtime -DryRun`; optionally install with `-InstallRuntime` and run global runtime verification | runtime payload changed and sync preview matters | docs-only changes or changes that clearly do not affect runtime payload |
| Full | Standard with runtime install, global verification, and deterministic harness evals | hooks, agents, workflow-control scripts, evals, sync scripts, public-readiness rules, verification envelopes, job-state/learning/component workflow, or release-critical changes | routine docs/skill/template edits already covered by Fast or Standard |

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
- The weekly automation template has placeholders and no machine-local path.
- Forbidden runtime files are absent from `src/`.
- PowerShell scripts parse.
- JSON manifests parse.
- Every published skill includes a loadable `SKILL.md` that starts with YAML
  frontmatter in UTF-8 without BOM, and its `name` matches the skill folder.
- Runtime/source sync boundary fixtures prove that backup files, archived
  payloads, and `.codex-private` skills do not cross into the public package.
- Standalone custom-agent files include portable `name`, `description`, and
  `developer_instructions` fields.

## Workflow-Core Regression Set

Use this set when the Codex workflow core changed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\test-codex-workflow-core.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-verification-envelope.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-project-harness-optimizer.ps1"
```

These checks cover hook lifecycle closure, verification envelope records,
workflow-core invariants, and the project harness optimizer expectations that
route trace/tool-eval and learning follow-up.

The workflow-core check also rejects hook fields that the current Codex CLI
does not support for that lifecycle event. Static JSON validity is not enough.

## Runtime Verification

Run this after intentionally syncing to `$env:USERPROFILE\.codex`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
```

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
| Hooks, sub-agent guardrails, or workflow entrypoints | workflow-core regression set | Full release gate |
| Verification envelope or gate scripts | `test-verification-envelope.ps1` | Full release gate and runtime verification |
| Trace/tool-eval closure or learning intake routing | `run-harness-evals.ps1` | Full release gate when shared harness behavior changed |
| Context budget, job-state, or component registry policy | targeted script run plus package verification | Full release gate if the shared harness contract changed |

For hook or custom-agent contract changes, add one bounded real Codex CLI run
after the deterministic checks. Keep it read-only and ephemeral, and verify the
expected lifecycle or subagent event from the CLI output. Treat provider,
plugin, or optional MCP warnings separately from task-caused harness failures.
