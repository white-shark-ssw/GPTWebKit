# Current Work — Development Router

This file routes Development/Feature sessions to one concrete task. It does not store a specific feature's Active body.

Active task checkpoints live at `docs/project/current/dev/<Work-ID>.md`.
Rules/template: `docs/project/current/dev/README.md`.

## Direct task routing

Users may say `当前为功能会话，新任务：<功能名>`, `当前为开发会话，新任务：<功能名>`, `当前为功能会话，继续 DEV-<slug>`, `当前为开发会话，继续 <明确任务名>`, or simply a concrete feature name such as `详情页优化`.

For existing tasks, matching priority:

1. exact Work ID;
2. clear Task name;
3. explicit `Routing aliases / keywords`;
4. one uniquely explainable strong keyword match.

Only one unique strong match may auto-select an Active task.

If zero or multiple tasks match, or similarity is fuzzy, list candidates and ask the user to choose. Do not guess and do not automatically create a new task. Even if only one Active task exists, Active status alone is not enough to assume continuation.

## Before selecting/creating a task

Do not create/modify a feature checkpoint, create/switch/reuse a feature branch, or change product code until concrete task identity is clear.

## Existing task resume identity guard

Before editing:

1. read the selected checkpoint;
2. verify real branch;
3. verify recorded PR if any;
4. verify head commit;
5. verify version/build/test candidate and artifact identity if allocated;
6. compare all other Active checkpoints for duplicate branch/candidate identity;
7. check whether base/target branch materially advanced.

Mismatch → stop and report. Never guess or silently rewrite task identity.

## New task preflight

Before creating a new parallel task, scan all Active checkpoints and compare files/modules in scope, state owners/shared infrastructure, Frozen/Stable contracts, unmerged dependencies, branch naming and candidate identity availability.

If parallel safety is doubtful, tell the user and prefer serial work or explicitly recorded stacked/dependent work.

## Current tasks

Do not maintain a hand-written dynamic task list here. Actual `current/dev/DEV-*.md` files are the source of truth.

## Completion

When a task completes, update durable project docs and remove only that task's current checkpoint. Keep history in Git/PR/build-test index.
