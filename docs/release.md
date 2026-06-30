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
| Full | `.\deploy\verify-release.ps1 -Level Full` | Installs runtime, runs global verification, and runs deterministic harness evals. |

Use Full for hook, agent, workflow-control, eval, sync, public-readiness, or
release-critical changes. Use Fast for docs, templates, skills, and low-risk
script edits.

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
- No private API tokens.
- No raw prompt payload dumps.
- No business project source code.

## GitHub Name

GitHub repository names are unique per owner. `codex-harness` is acceptable
even if other accounts already use the same repository name.
