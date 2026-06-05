# Skill Surface

The active skill set should stay focused and triggerable. Skill surface reviews
are read-only by default; archive actions stay manual and reversible.

## Command

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\audit-skill-surface.ps1"
```

## Review Criteria

- missing or weak frontmatter
- vague descriptions
- provider-specific assumptions
- duplicated or overlapping skills
- oversized skills that should move detail into references
- domain skills that should be archived unless an active project needs them

## Output

Reports are written under `harness-health/skill-surface/`. Treat the report as
an advisory stocktake, not an automatic cleanup plan.
