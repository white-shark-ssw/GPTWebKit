# Parallel Development Checkpoints

This directory contains only currently active Development/Feature task checkpoints.

Each task has one stable Work ID: `DEV-<short-slug>`.

## Required identity

Each Active task must have a unique Work ID, its own checkpoint file, stable `Routing aliases / keywords`, its own development branch, its own PR when appropriate, and its own candidate identity when producing testable artifacts.

Two Active tasks must never share the same development branch.

## Human-friendly task matching

Checkpoint routing should be explainable, not a black-box guess.

`Routing aliases / keywords` should include short names the user is likely to say, for example: `详情页优化 / 详情页 / 媒体详情`.

Automatic selection is allowed only when one Active task uniquely and strongly matches through Work ID, Task, or aliases/keywords. Multiple/weak/no matches → ask the user.

## Parallel-safety preflight

Before creating a new task, scan all Active checkpoints and compare Files/modules in scope, State owner/shared dependencies, Frozen/Stable contracts, shared infrastructure, unmerged dependencies, Working branch, and allocated candidate identities.

Do not silently parallelize tasks that may modify the same file, same state owner, same critical/frozen core, or depend on unmerged work.

## Candidate identity

Follow the real project versioning scheme in `PROJECT_PROFILE.md`.

Before allocating a version/build/test candidate, inspect `BUILD_TEST_INDEX.md`, all Active checkpoints, real version/build source, and CI/artifact/release identities.

No two Active tasks may share the same exact build number, version/build tuple, release tag, artifact name or candidate ID.

## Checkpoint template

```md
# DEV-<slug>

## Status

**Active**

- **Work ID**: `DEV-<slug>`
- **Routing aliases / keywords**: `<short names separated by / >`
- **Task**:
- **User intent / acceptance criteria**:
- **Baseline**: version / build / base branch / base commit / accepted runtime baseline
- **Working branch / PR / head commit**:
- **Candidate identity**: version / build / tag / artifact / test candidate, or `Not allocated`
- **Evidence**:
- **Files / modules in scope**:
- **State owner / shared dependencies**:
- **Frozen / do-not-touch**:
- **Parallel conflicts checked against**:
- **Completed**:
- **Validation state**:
- **Pending**:
- **Next exact action**:
- **Rejected / do-not-repeat**:
- **Open questions / risks**:
```

## Proactive update milestones

Update this task checkpoint without waiting for user reminders when baseline/branch/PR/head is confirmed, first effective code exists, tests/CI change, artifact/candidate is produced, runtime/manual result arrives, hypothesis is rejected, scope/state ownership changes, dependency/candidate identity changes, or the next exact action materially changes.

## Completion

When complete, update durable project docs, record final validation/candidate identity in `BUILD_TEST_INDEX.md`, remove this task's current checkpoint, leave all other Active checkpoints untouched, and keep historical evidence in Git/PR/index.
