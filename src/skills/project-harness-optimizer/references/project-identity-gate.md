# Project Identity Gate

Use this preflight before project onboarding, architecture work, roadmap work,
or harness optimization when the directory's role is not already trustworthy.
It prevents a visible file or coherent cluster from being promoted into the
purpose of the whole workspace.

## Trigger

Run the gate when one or more conditions hold:

- the request says "this project", "this folder", or "this repository" without
  naming the authoritative target or desired outcome
- trustworthy pre-existing root purpose anchors are missing or contradictory
- the directory is not a clear repository, or it resembles a vault, template
  library, asset collection, archive, operations workspace, or mixed workspace
- several assets could each be the intended project
- the request combines analysis, harness optimization, architecture, or roadmap
  creation but does not define what should be analyzed or changed

The gate precedes maintenance-lane selection. It is not an Audit Only request
and does not prevent later implementation; it prevents premature commitment.

## Evidence Ladder

Rank evidence in this order:

1. The user's explicit statement in the current conversation.
2. Pre-existing root instructions, mission, README, manifests, or project docs.
3. Consistent Git, package, build, runtime, and deployment metadata.
4. Folder names, individual documents, similar files, and adjacent directories.

The fourth level supports hypotheses only. A file created during the current
task is generated evidence and cannot validate the premise that produced it.
Conversation history can explain intent, but the user's newest statement wins.

## Classification And Confidence

Use the closest workspace type:

- software repository or product
- content or document vault
- template library
- skill or asset collection
- archive or package
- operations workspace
- mixed workspace
- unknown

Assign confidence:

- `high`: explicit current-user purpose, or strong consistent pre-existing root
  evidence with no material contradiction
- `medium`: consistent technical metadata but no authoritative purpose or
  unresolved scope boundary
- `low`: purpose inferred mainly from a folder name, one salient file, a small
  cluster, neighboring folders, or anchors generated during the current task

## Read-Only Discovery

Before asking, perform only a bounded inventory: inspect root names, Git state,
pre-existing anchors and manifests, and a representative sample. Do not exhaust
the directory or read unrelated private content merely to avoid asking.

At `high` confidence, state the identity in one sentence and proceed. At
`medium` or `low` confidence, present:

- `Observed`: direct facts from the inventory
- `Inferred`: plausible interpretations, labeled as hypotheses
- `Unknown`: decisions only the user can supply

Then ask one compact brainstorming round of at most three questions:

1. What role does this directory serve, and which file, subdirectory, or asset
   is the authoritative project target?
2. Who or what workflow is it for, and what architecture or organizational
   boundaries should it have?
3. What final outcome and success criteria matter, and should Codex only propose
   a direction or implement it within which allowed scope?

Combine or omit questions already answered. Use vocabulary appropriate to the
workspace: information architecture for a document vault, organization and
metadata for a template library, and software architecture for a codebase.

## Identity Lock

Synthesize the answer into a compact project brief:

- workspace type and authoritative target
- intended users or workflow
- current state and intended architecture or organization
- purpose and non-goals
- final outcome and success criteria
- allowed change scope and whether implementation is authorized

An explicit user answer that resolves these fields establishes the identity
lock; do not demand ceremonial confirmation. If material ambiguity remains,
show the provisional brief and ask the user to confirm or correct it.

Until the lock exists, do not write files, extract or reorganize assets, create
scaffolds, architecture docs, roadmaps, plans, or durable records, or launch
implementation subagents. A generic "continue" or "do it" does not waive an
unresolved identity question. At most one read-only explorer may help classify
a large workspace; no fan-out is allowed before the lock.

## Corrections

When the user corrects the project premise:

1. Stop work based on the old premise.
2. Reclassify using the user's statement as highest-priority evidence.
3. Find durable anchors generated from or conflicting with the old premise.
4. Reconcile those anchors before continuing implementation.
5. Report what changed in the project brief and what remains untouched.

## Regression Examples

- One topical note in a document vault does not define the whole vault.
- Similar workflow exports may be a template library, not one business system.
- One archive in a skill or asset collection is not automatically the target to
  extract, productize, or roadmap.

All three stay read-only and ask before writing unless stronger evidence raises
confidence to `high`.
