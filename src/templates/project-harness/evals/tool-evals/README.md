# Tool Evals

This folder holds lightweight fixtures for checking whether tool surfaces are
clear enough for an agent to choose the right tool, map parameters, keep
multi-turn context, and avoid unsafe calls.

These fixtures are intentionally local and text-based. They are a harness layer,
not a hosted benchmark or a full MCP runtime.

## Cases

Put cases under `cases/` as JSON or simple YAML.

Recommended lanes:

- `tool-selection`: the model should choose the intended tool.
- `param-mapping`: user wording should map to the intended argument shape.
- `multi-turn`: later turns should preserve relevant prior context.
- `safety`: risky or injected requests should be refused or gated.
- `tool-error`: error recovery should use the documented path.

Run:

```powershell
.\scripts\check-tool-evals.ps1
```

JSON cases get full structural validation. YAML cases get dependency-free
top-level structural lint so the harness stays portable on Windows.
