# START HERE

This is the repository's AI work entry point.

## Startup order

1. Read repository root `AGENTS.md`.
2. Read `CURRENT_WORK.md` and determine Rules vs Development/Feature from the user's current message.
3. Read `PROJECT_PROFILE.md`, `PROJECT_STATE.md`, `MODULE_STATUS.md`, `TECHNICAL_DECISIONS.md`, `BUILD_TEST_INDEX.md`, `PROJECT_SPECIFIC_RULES.md`, and `DOCUMENTATION_POLICY.md`.
4. If `PROJECT_PROFILE.md` says `Initialization: Pending`, perform repository bootstrap according to `AGENTS.md` before substantive development.
5. For Rules work, use `CURRENT_WORK_RULES.md`.
6. For Development/Feature work, use `CURRENT_WORK_DEV.md` and exactly one selected checkpoint under `current/dev/`.

Do not ask the user to upload project documents that already exist in this repository.

## Source of truth

Current real source and current task branch evidence take priority over stale documentation. Runtime/user test evidence takes priority over CI-only assumptions.

If the repository changed since docs were last updated, verify real state and proactively correct docs in the same work cycle.

## History

Do not require old chat exports as a normal startup dependency. Only consult historical material when current source and current project docs cannot resolve a specific historical question.
