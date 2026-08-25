# Current Work Router

This file routes the current conversation type. It does not hold feature-task details.

## Session types

- Rules / governance → `CURRENT_WORK_RULES.md`
- Development / feature / bug / investigation → `CURRENT_WORK_DEV.md`

Explicit aliases:

- `当前为规则会话` → Rules
- `当前为开发会话` → Development/Feature
- `当前为功能会话` → Development/Feature

A bare concrete feature name may route directly to an existing Active development task only when it uniquely and strongly matches one checkpoint by Work ID, Task, or explicit `Routing aliases / keywords`.

## Ambiguity stop

If the user's current message does not reliably identify Rules vs Development/Feature, tell the user that the session type is unclear and ask them to choose.

Do not infer from which task is Active, recent updates, previous chat topic, urgency, or model preference. Before the user chooses, do not activate/modify checkpoints, switch branches, or start work.

## Development task routing

After routing to Development/Feature, read `CURRENT_WORK_DEV.md`.

If a direct feature name uniquely identifies an Active task, run its resume identity guard before editing code.

If there are zero or multiple matches, ask the user to choose or explicitly say it is a new task. Never auto-create a task from an unmatched phrase.

## Isolation

Rules work must not modify an Active development checkpoint merely to finish governance work. Each development session maintains exactly one selected task checkpoint and leaves all others untouched.
