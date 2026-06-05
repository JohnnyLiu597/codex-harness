# Mission

Maintain a small, reliable, Codex-only agent harness as a versioned project.

The harness should make Codex better at long-running engineering work by
providing stable instructions, focused skills, safe local scripts, project
templates, deterministic evals, runtime evidence records, and verification
gates.

## Non-Negotiables

- Codex-only by default.
- Windows-first and PowerShell-first.
- No secrets or runtime databases in source.
- Runtime install target: `C:\Users\Johnny Liu\.codex`.
- Source-of-truth project: this repository.
- Verify before claiming harness changes are complete.

## Success Criteria

- `src/` contains the maintainable harness payload.
- `deploy/verify-package.ps1` passes.
- `deploy/sync-to-runtime.ps1 -DryRun` clearly reports what would sync.
- Runtime verification and harness evals pass after installation.
- GitHub-ready files are separated from local runtime state.
