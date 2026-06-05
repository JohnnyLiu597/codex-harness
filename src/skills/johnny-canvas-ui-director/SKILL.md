---
name: johnny-canvas-ui-director
description: Use when designing, reviewing, or implementing Johnny Canvas UI, Figma frames, design systems, canvas nodes, workbench panels, or visual direction.
---

# Johnny Canvas UI Director

## Purpose

Keep Johnny Canvas UI work from drifting into generic AI app aesthetics. This
skill applies only to Johnny Canvas design, Figma, and frontend UI tasks.

## Direction

Johnny Canvas is a professional AI video production workbench for short-drama,
comic-drama, storyboard, and media-generation workflows.

Use this direction:

- Primary reference: LibTV-like dense production workbench.
- Secondary reference: TapNow-like canvas affordances, node labels, and add
  menu behavior.
- Product tone: quiet, operational, premium, fast to scan, built for repeated
  production work.
- Visual density: dense but organized, closer to an editor than a SaaS landing
  page.
- Language: Simplified Chinese for visible UI copy, except product names,
  provider names, file formats, code, and proper nouns.

## Non-Negotiables

- Do not create landing pages, marketing heroes, decorative dashboards, or
  oversized empty cards.
- Do not use purple-blue gradient SaaS styling, beige/brown palettes, cute
  illustrations, decorative blobs, or generic AI portfolio aesthetics.
- Do not add Tailwind, shadcn, Radix, or a new icon package just because a
  Figma or design skill suggests it. Follow the repo stack first.
- Do not copy old AIMIX code or naming into Johnny Canvas.
- Do not persist secrets, tokens, cookies, auth data, runtime job state, or web
  sessions in project files.
- Do not make Figma a loose moodboard. It must define tokens, components,
  states, measurements, and implementation intent.

## Figma Workflow

Use this order for design work:

1. Read project anchors: `docs/design.md`, `docs/prd.md`, `docs/code-map.md`,
   and the newest relevant `artifacts/plan_*.md`.
2. Inspect the current Figma file before writing.
3. Create or update a design-system page before creating new screen variants.
4. Define tokens first: colors, typography, spacing, radii, shadows, state
   colors, z-depth, and canvas grid metrics.
5. Build reusable components before composing screens.
6. Create screen frames only from those components.
7. Validate with screenshots and compare against the design direction.

## Token Targets

Start from the app's current CSS variables, then refine:

- `--surface-0` through `--surface-3` for dark workbench layers.
- `--line-soft` and `--line-strong` for low-noise separators.
- `--text-strong`, `--text-main`, and `--text-soft`.
- `--accent`, `--accent-strong`, `--accent-soft`.
- `--warning`, `--danger`, `--success`.
- `--node-radius` and `--panel-radius`, normally 8px or less.

Use a dark neutral base with one controlled accent. Add media-type color only
as small status marks, badges, ports, or graph affordances.

## Component Scope

For Johnny Canvas v1, prioritize:

- Workbench shell: top project bar, left tool dock, canvas, bottom controls.
- Node shell: floating label, selected state, preview body, ports, status.
- Media nodes: image, video, audio, output chips, final pick state.
- Production nodes: text, script, storyboard, AI agent, video composition,
  group/scene-section.
- Panels: asset library, story library, task queue, model profiles, settings.
- Generation controls: provider route summary, cost confirmation, queue intent.
- Tables: storyboard rows, shot lineage, variants, final selections.

## Design Rules

- Use compact controls, real icons, tooltips, segmented controls, inputs,
  toggles, menus, tabs, and dense tables where appropriate.
- Keep selected editors near the selected node or in contextual panels.
- Show media thumbnails or stable placeholders, never vague decorative art.
- Preserve 1000-node canvas usability: small labels, stable node dimensions,
  minimal reflow, and low visual noise at zoomed-out states.
- Make state obvious: empty, queued, running, success, error, cancelled, retry,
  selected, linked, missing asset, and final pick.
- Separate asset history from runtime task logs.
- Treat paid provider actions as confirm-then-queue flows.

## When Using Community UI Skills

Use downloaded design skills as critique tools, not as authority. If a skill
suggests a style that conflicts with Johnny Canvas, this skill wins.

- `redesign-skill`: useful for auditing generic UI weaknesses.
- `ui-ux-pro-max`: useful for palettes, typography, and UX pattern lookup.
- `frontend-design-anchors`: useful for avoiding default aesthetics, but choose
  an editor/workbench direction, not an unrelated expressive anchor.
- `taste-skill`: useful for raising visual intentionality; ignore stack
  assumptions that do not match this repo.
- `brandkit`: useful for brand-system thinking, not for replacing the workbench
  with a brand moodboard.

## Acceptance Check

Before calling a Johnny Canvas UI/Figma task done, verify:

- The first viewport is the actual canvas/workbench.
- The design can support hundreds of nodes and repeated production workflows.
- Tokens and components are reusable, named, and documented.
- UI copy is Chinese and names real product behavior.
- Screenshots do not read as generic AI SaaS, marketing, or moodboard output.
- Implementation notes map back to React, TypeScript, React Flow, Zustand, and
  CSS variables in this repository.
