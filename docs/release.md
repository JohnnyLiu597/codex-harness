# Release Workflow

This project can be published to GitHub after public-readiness review.
Release work uses the Source Release lane: edit `src/`, verify the package,
preview/install to runtime, then run runtime verification. Routine harness
maintenance should use the Runtime Hotfix lane instead.

## Local Release Checklist

1. Run `.\deploy\verify-package.ps1`.
2. Run `.\deploy\sync-to-runtime.ps1 -DryRun`.
3. Install with `.\deploy\sync-to-runtime.ps1`.
4. Run global runtime verification.
5. Run deterministic harness evals.
6. Review `git status`.
7. Commit.

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
