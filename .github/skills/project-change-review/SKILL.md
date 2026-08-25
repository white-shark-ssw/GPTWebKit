# Project Change Review Skill

Use before finalizing a meaningful code change.

## A. Identity and baseline

Confirm selected Work ID, checkpoint path, base branch/commit, working branch, PR if any, head commit, candidate/version/build/artifact identity if allocated, and no duplicate branch/candidate identity in another Active checkpoint. Inconsistency → stop.

## B. Evidence

Confirm the change is justified by current source, tests/logs, reproducible behavior, explicit user requirement, or verified compatibility/dependency constraint. No evidence → do not manufacture a patch.

## C. Scope

Reject unrelated refactor, guessed API, duplicate state owner, speculative abstraction, silent error swallowing, catch-all fallback, unbounded retry/recovery, timer/watchdog hiding lifecycle bugs, unnecessary compatibility shim, or broad formatting churn.

## D. Parallel conflict

Compare other Active tasks for same files, same state owner, Frozen/Stable core overlap, shared infrastructure, unmerged dependency, branch reuse, and candidate/build/version/artifact reuse. Conflict → report and serialize or explicitly stack.

## E. Validation

Run the narrowest meaningful checks first. Before final CI/artifact/merge, re-check whether target branch advanced and whether synchronization invalidates old evidence.

Keep evidence labels distinct: Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, Stable/Frozen.

## F. Documentation

Update the selected task checkpoint and durable project docs whose truth changed in the same work cycle. Do not touch another task's checkpoint.
