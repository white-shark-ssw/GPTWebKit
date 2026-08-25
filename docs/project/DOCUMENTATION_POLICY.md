# Documentation Policy

## Purpose

`docs/project/` is the current authoritative handoff layer for AI-assisted development. The user should not need to feed these files into every new conversation. AI agents should read and maintain them directly from the repository.

## Required documents

`START_HERE.md`, `PROJECT_PROFILE.md`, `PROJECT_STATE.md`, `MODULE_STATUS.md`, `TECHNICAL_DECISIONS.md`, `BUILD_TEST_INDEX.md`, `PROJECT_SPECIFIC_RULES.md`, `CURRENT_WORK.md`, `CURRENT_WORK_RULES.md`, `CURRENT_WORK_DEV.md`, and `current/dev/README.md`.

## Automatic initialization

When `PROJECT_PROFILE.md` is Pending, initialize the project from repository evidence. Identify project purpose, languages/frameworks, dependencies/package managers, source/test roots, build/test/lint commands, CI workflows, version/build source, artifact/release scheme, runtime/deployment targets, key modules/state owners, and current accepted baseline/candidates where verifiable.

Unknown facts remain Unknown/Unverified.

## Authority priority

When facts conflict:

1. latest explicit user runtime/test result or requirement;
2. current real source on the relevant branch/commit;
3. current CI/artifact/test evidence;
4. current `docs/project/`;
5. old history/plans.

## Proactive maintenance

Do not wait for the user to ask for documentation updates. Update relevant current checkpoint and durable docs in the same work cycle after meaningful implementation, test/CI/artifact changes, runtime/manual results, architecture decisions, dependency changes, version/build/deployment changes, module status/freeze changes, project-profile changes, or accepted baseline changes.

Avoid noisy updates for every tiny edit.

## Session-limit resilience

Conversation limits are unpredictable. Create task checkpoints early after goal + usable baseline/direction are clear.

Keep the latest checkpoint sufficient for a new session to know what task is active, which branch/PR/commit/candidate it owns, what is done, current evidence, what remains, exact next action, rejected routes and conflict risks.

## Parallel isolation

Rules and multiple development tasks may all be Active. Each development task writes only its own checkpoint. Rules work writes only the rules checkpoint and durable rule files. No session may clear, merge or repurpose another Active task's checkpoint.

## Completion

Development completion moves durable conclusions to long-term docs, records final validation/candidate in the index, and removes only that task's current checkpoint. Rules completion moves durable rules to permanent rule files and resets only the rules checkpoint to Idle.
