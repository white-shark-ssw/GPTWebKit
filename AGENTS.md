# Repository AI Governance Rules

This file is the repository-wide standing instruction for AI coding agents.

## 1. Start from repository truth

Before changing code:

1. Read `docs/project/START_HERE.md`.
2. Read `docs/project/CURRENT_WORK.md` and route the session type.
3. Read the selected task checkpoint and relevant project-state documents.
4. Resolve the real source baseline: branch / PR / commit / version / build or test candidate when applicable.
5. Inspect real definitions, call sites, state owners, tests, logs, build files and CI configuration before proposing changes.
6. If source evidence contradicts an earlier assumption or document, change the assumption and update durable docs after verification.

Do not ask the user to re-upload or re-explain project information that already exists in the repository.
Do not invent APIs, variables, functions, commands, framework behavior, repository structure, build steps or version locations.

## 2. Automatic project initialization

If `docs/project/PROJECT_PROFILE.md` says `Initialization: Pending`, perform repository bootstrap before substantive development:

- inspect README/docs and repository tree;
- identify primary purpose and product type;
- identify languages, frameworks and dependency/package manifests;
- identify build, test, lint and formatting commands from real config;
- identify CI/workflow entry points;
- identify version/build-number sources and artifact naming;
- identify runtime/deployment targets where evidence exists;
- identify major modules and likely state owners from source structure;
- identify current baseline branches/PRs/releases/test candidates where available.

Write verified findings into `PROJECT_PROFILE.md`, `PROJECT_STATE.md`, `MODULE_STATUS.md`, `TECHNICAL_DECISIONS.md`, `BUILD_TEST_INDEX.md`, and `PROJECT_SPECIFIC_RULES.md` only when supported by evidence or explicit user requirement.

Unknown facts must remain `Unknown / Unverified`. Never guess to make initialization look complete. Initialization is documentation/governance work; do not change product code unless the current user task requires it.

## 3. Session routing

Explicit aliases:

- `当前为规则会话` → Rules
- `当前为开发会话` → Development/Feature
- `当前为功能会话` → Development/Feature

A bare concrete feature name can identify a Development/Feature task only when it uniquely and strongly matches one Active development checkpoint by Work ID, Task, or explicit `Routing aliases / keywords`.

If Rules vs Development/Feature cannot be determined from the user's current message, stop and ask the user to choose. Do not activate anything, switch branches, or start work. Active/Idle state alone is never routing evidence.

Rules work uses `docs/project/CURRENT_WORK_RULES.md`.
Development work uses `docs/project/CURRENT_WORK_DEV.md` and one selected `docs/project/current/dev/<Work-ID>.md`.

## 4. Development task selection

For existing Active development tasks, matching priority is:

1. exact Work ID;
2. clear Task name;
3. explicit `Routing aliases / keywords`;
4. one uniquely explainable strong keyword match.

If zero or multiple tasks match, or the match is only fuzzy semantic similarity, list candidates and ask the user to choose. Do not silently select one and do not auto-create a new task merely because no task matched.

Even if only one task is Active, do not assume continuation unless the user's message identifies it.

Before a task is selected, do not modify a development checkpoint and do not create/switch/reuse a feature branch.

## 5. Resume identity guard

After selecting an existing task and before editing product code:

- verify the checkpoint's branch exists and is the intended working branch;
- verify PR identity if recorded;
- verify current head commit;
- verify allocated version/build/test candidate and artifact identity;
- compare other Active checkpoints for duplicate branch or candidate identity;
- check whether the target/base branch advanced materially.

If checkpoint and GitHub/source facts disagree, stop and report the mismatch. Do not guess which record is correct and do not silently overwrite another task's identity.

## 6. Evidence-first minimal change

Only change code when justified by current source, logs, reproducible behavior, tests, explicit requirements, or verified compatibility constraints.

Prefer the smallest change that fixes the identified invariant.

Do not add without current evidence:

- speculative retry;
- fallback;
- timer;
- watchdog;
- duplicate state;
- compatibility shim;
- silent error swallowing;
- catch-all recovery loops;
- future-only abstraction;
- unrelated refactor or formatting churn.

If evidence does not justify a code change, say so instead of manufacturing a patch.

## 7. State ownership and defensive code

For every new fallback, timeout, guard, retry, recovery path or state cache, explain the concrete failure mode, true state owner, why the normal path is insufficient, how the fallback terminates, and why it will not create a second authority. Prefer fixing the invariant at its owner.

## 8. Project-specific contracts and Frozen modules

Read `docs/project/PROJECT_SPECIFIC_RULES.md` and `docs/project/MODULE_STATUS.md` before touching modules marked Frozen/Stable or changing a documented contract.

Do not casually change a Frozen module for unrelated work. If a task truly requires it, state the exact reason/evidence first and update module status after the result is known.

## 9. Parallel development discipline

Multiple feature-development sessions are allowed only with isolation.

Each Active feature task must have:

- unique Work ID;
- its own `docs/project/current/dev/<Work-ID>.md` checkpoint;
- stable `Routing aliases / keywords`;
- its own development branch;
- its own PR once appropriate;
- its own unique test identity when artifacts/builds are produced.

Two Active tasks must never share the same development branch.

Before creating a new parallel task, inspect all other Active checkpoints for overlap in files/modules, state owners, Frozen/stable contracts, shared infrastructure and unmerged dependencies.

If tasks may modify the same source file, same core state owner, same Frozen/shared core, or one depends on another unmerged task, do not silently run them as independent parallel work. Tell the user about the conflict. Prefer serial work, or explicitly record stacked/dependent work.

Git mergeability is not proof of architectural parallel safety.

## 10. Version / build / artifact identity

Follow the project's real versioning scheme recorded in `PROJECT_PROFILE.md`.

When a parallel task reaches a runnable/testable artifact stage, it must have a unique candidate identity. Before allocating it, inspect `BUILD_TEST_INDEX.md`, all other Active checkpoints, existing CI artifacts/releases/test candidates, and the project's actual version/build source.

Do not reuse the same build number, exact version/build tuple, artifact name, release tag or candidate ID for two Active tasks. Once allocated, treat the task's candidate identity as reserved until explicitly completed/released and documented.

If the project does not use numeric build numbers, use its existing release/test convention. If no convention exists, establish a minimal candidate scheme in `PROJECT_PROFILE.md` before producing ambiguous artifacts.

## 11. Validation evidence

At minimum distinguish:

1. **Code written**
2. **Static/local checks passed**
3. **CI passed**
4. **Artifact produced**
5. **Runtime/manual/real-device tested**
6. **Stable / frozen**

Never describe CI or artifact generation as proof that a runtime issue is solved.

## 12. Before final CI / artifact / merge

Parallel work can move the target branch. Before final CI/artifact/merge, check whether target/base advanced, re-check file/state-owner/dependency overlap, synchronize when appropriate, determine whether tested code materially changed, and rerun affected validation if it did. Old CI does not prove synchronized code passes.

## 13. Automatic documentation and proactive checkpointing

Do not wait for the user to request status updates.

For multi-step work, create/update the selected checkpoint early once goal and usable baseline/direction are known. The conversation/context limit is unpredictable.

Refresh the selected checkpoint at meaningful milestones, including baseline/branch/PR/commit confirmation, first effective code/rule decision, CI/test/artifact changes, runtime/manual results, architecture decisions, rejected hypotheses, dependency/version/build/deployment changes, scope changes or next-action changes.

Also update durable project documents in the same work cycle when their truth changes. Do not update docs for every tiny edit. Keep the latest checkpoint only one small meaningful milestone behind the live conversation.

Each development session modifies only its own task checkpoint. Rules work modifies only the rules checkpoint and durable rule files.

## 14. Completion

When a development task completes:

1. move durable conclusions to the appropriate project docs;
2. record final branch/PR/version/build/test evidence;
3. remove only that task's current checkpoint;
4. leave all other Active task checkpoints untouched.

When a rules task completes, move durable rules to permanent rule files and reset only `CURRENT_WORK_RULES.md` to Idle.

## 15. Conflict priority

When evidence conflicts, prefer:

1. user's latest explicit runtime/test result or requirement;
2. current real source on the relevant branch/commit;
3. current CI/artifact/test evidence;
4. current `docs/project/` state;
5. old history/plans.

Never treat an old plan as proof that code exists.
