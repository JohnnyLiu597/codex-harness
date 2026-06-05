---
name: skill-stocktake
description: Audit the active Codex skill surface for duplicates, stale provider-specific content, oversized skills, and low-value long-tail packs.
origin: local-codex-harness
---

# Codex Skill Stocktake

Use this when auditing the active Codex skill directory after imports,
cleanup, or harness upgrades.

## Scope

Default scan targets:

- `~/.codex/skills/`
- `{cwd}/.codex/skills/` if present
- `{cwd}/skills/` only if the project explicitly uses local skills

Do not scan archived directories unless the user asks to restore or compare
archived skills.

## Checklist

For each skill, check:

- Frontmatter exists and includes `name` and `description`.
- Description is triggerable and specific.
- Content is actionable for Codex.
- Provider-specific claims do not assume external agent runtimes unless the
  skill is explicitly about those tools.
- The skill is not substantially duplicated by another active skill.
- The skill is not so broad that it should be split or archived.

## Recommended Verdicts

- `Keep`: useful, current, and Codex-applicable.
- `Improve`: useful but needs clearer trigger, shorter content, or Codex wording.
- `Archive`: valid but niche or not needed in the active Codex surface.
- `Retire`: stale, broken, duplicate, or unsafe to keep.
- `Restore`: archived skill should become active for the current project.

## Output

Return a compact table:

| Skill | Verdict | Reason |
| --- | --- | --- |

Include:

- active skill count
- missing frontmatter count
- largest skills by size
- provider-specific skills found in active surface
- recommended archive/restore actions

Prefer reversible archive moves over permanent deletion unless the user asks for
hard deletion.
