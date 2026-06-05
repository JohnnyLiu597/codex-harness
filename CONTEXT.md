# Context

This project was created after the active Codex harness had already been
upgraded in `C:\Users\Johnny Liu\.codex`.

Current source direction:

- Import the current runtime's maintainable assets into `src/`.
- Keep `.codex` runtime files such as auth, SQLite state, logs, sessions,
  plugin cache, and temporary files out of this repository.
- Keep old `C:\Users\Johnny Liu\Claudecowork\Harness` as historical reference
  only. It contains older cross-runtime harness material and should not be
  used as the current project root.

Next maintenance step after initialization:

- Review `src/` for public GitHub readiness, especially personal paths and
  machine-specific documentation.
