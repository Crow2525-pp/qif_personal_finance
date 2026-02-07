# Agents Index

Use these guidance agents from claude.ai/code to handle higher-level tasks.

- `project-architect` — Evaluate project structure, spot redundancy/bloat, and recommend cleanup/refactors. Trigger when you need a structural review, are unsure about keeping files/modules, or want a lean pass after adding features. Definition: `.claude/agents/project-architect.md`.

Adding more agents: place the definition file in this folder, then add a one-line summary here with when-to-use cues so people can pick the right agent quickly.

## Task Tracking Rule

- When a job is completed and verified, move it from active backlog files (for example `todo-fix.md`) into `done.md`.
- Do not leave completed jobs in todo files.
