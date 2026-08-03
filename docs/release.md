# Release Workflow

This project can be published to GitHub after public-readiness review.
Release work uses the Source Release lane: edit `src/`, run the lowest
sufficient release gate, then commit/push. Routine harness maintenance should
use the Runtime Hotfix lane instead.

## Release Gates

| Gate | Command | Purpose |
|---|---|---|
| Fast | `.\deploy\verify-release.ps1 -Level Fast` | Default before GitHub push. Checks whitespace and package public-readiness without runtime install or evals. |
| Standard | `.\deploy\verify-release.ps1 -Level Standard` | Adds runtime sync preview. Add `-InstallRuntime` when the current local runtime should receive the source change. |
| Full | `.\deploy\verify-release.ps1 -Level Full` | Installs runtime, runs global verification, and runs deterministic harness evals. Required when workflow-core, hook, verification, eval, sync, or publication-boundary behavior changed. |

Use Full for hook, agent, workflow-control, eval, sync, public-readiness, or
release-critical changes. Use Fast for docs, templates, skills, and low-risk
script edits.

This documentation closure follows the Full path because it describes the
current workflow-core upgrade rather than a wording-only docs refresh.

## Local Release Checklist

1. Classify the change as Fast, Standard, or Full.
2. Run `.\deploy\verify-release.ps1 -Level <Fast|Standard|Full>`.
3. Review `git status`.
4. Commit.
5. Push only when the user asked for GitHub publication.

Do not install runtime or run deterministic evals just because a commit will be
pushed. Install runtime when the active local Codex harness should receive the
source change; run evals when the changed behavior needs regression evidence.

## Public-Readiness Checklist

- No auth files.
- No SQLite databases.
- No logs or session transcripts.
- No browser profile data.
- No plugin cache.
- No generated images.
- No hook logs or hook state snapshots.
- No verification envelopes or raw step logs unless intentionally sanitized.
- No job-state, learning-intake, or ablation-run artifacts.
- No raw trace-eval or tool-eval output artifacts.
- No private API tokens.
- No raw prompt payload dumps.
- No business project source code.
- No backup-suffixed files, archived scripts, or runtime-only private skills.
- Custom agents are standalone and do not depend on unpublished role entries in
  runtime `config.toml`.

## Release Matrix

| Change surface | Gate | Notes |
|---|---|---|
| README/docs wording only | Fast | Keep runtime/source flow text aligned with actual scripts |
| Templates, skills, low-risk scripts | Fast | Escalate if sync or public-readiness rules changed |
| Runtime/source sync flow | Standard or Full | Use Full when install, exclusion, or verification behavior changed |
| Hooks, native sub-agents, verification envelope/gate, eval closure | Full | Includes this upgrade |
| Publication boundary or privacy exclusions | Full | Re-review ignored/generated artifacts before any public release |

## GitHub Name

GitHub repository names are unique per owner. `codex-harness` is acceptable
even if other accounts already use the same repository name.
