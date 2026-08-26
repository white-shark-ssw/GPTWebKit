# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别当前 ChatGPT iOS 会话，并确保 Pull / Reload / Export / Rename 只作用于真实当前 conversation；同时完善 Reload 完成语义和项目会话标题展示。
- **Acceptance invariant**: **Pull / Reload / Export / Rename 必须使用真实当前 conversation ID，不得串会话；同名会话必须可精确区分。Reload 请求发生不等于 Reload 完成；插件生成标题只能用于 presentation，永远不能反向成为 identity evidence。**

## Resume identity / conflict guard — 2026-08-26

- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked unchanged before alpha49 work.
- **Working branch / PR**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; branch/PR head rechecked at `17f76c8428dad41484641b9dcf23a78935dbc32f`, PR open/draft/mergeable, base SHA unchanged.
- **Parallel task**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43, Draft PR #3 stacked on this recognition branch. User explicitly said percentage work is out of scope here; alpha49 must not modify percentage-owned source/checkpoint.
- **Candidate uniqueness check**: alpha43 is reserved by the parallel task; recognition lineage has alpha46/47/48 already allocated. `ENH-0.1.0-alpha49-exact-rename-ui-target` is newly allocated and unique.

## Current candidate — alpha49

- **Candidate**: `ENH-0.1.0-alpha49-exact-rename-ui-target` / product `0.1.0-alpha49-exact-rename-ui-target`.
- **Source baseline for this candidate**: alpha48 post-CI product head `17f76c8428dad41484641b9dcf23a78935dbc32f`.
- **Scope approved by user**: begin the next evidence-backed fixes after alpha48 runtime findings.
- **Planned product changes**:
  1. restore enhancer `重命名会话` in the proven top-right current-chat menu using the same immutable exact `capturedID` contract as Pull/Reload/Export;
  2. re-check that exact ID immediately before rename PATCH execution; no title/source-view candidate heuristic may select the target;
  3. correct the shared UI target-discovery weakness exposed by alpha48: project-header presentation and Reload baseline capture currently start from `CEKeyWindow()` while invoked from a context-menu surface. Search visible windows of the foreground scene for the actual host content surface rather than assuming the transient key window is the conversation window;
  4. preserve alpha48 request + UI proof semantics; do not revert to request-only success;
  5. do **not** add generation `/resume`, speculative retry/watchdog/timer/status override. Interrupted-generation recovery still lacks a trace that begins before send/disconnect.
- **Validation state**: alpha49 **Code not yet written** at allocation time. No CI/artifact/runtime evidence yet.

## Authoritative alpha48 runtime evidence

- User-exported trace `6CC3B3D6-2F4F-40A1-9D84-CABB7D0C7F3B` kept exact Reload target stable and produced same-ID `conversation/init → f/conversation/prepare → conversation detail`; no cross-conversation evidence appeared.
- User visually observed the page refresh, but alpha48 logged `baselineUI=unproven` and never set `uiRebuildObserved`, proving the current UIKit snapshot can false-negative on the real host surface.
- The trace repeatedly had the correct exact-ID menu presentation title (`轮播图优化v1`), while the project header still showed the project name/no gear. Title acquisition is correct; presentation-target discovery/application is failing.
- The interrupted response remained stuck at `正在思考` after the page refresh. The trace began after the original disconnect and shows no recorded generation-resume sequence, so generation recovery remains unproven and out of alpha49 scope.
- User also confirmed the plugin custom `重命名会话` entry disappeared. Source comparison proves alpha47's exact-menu rewrite dropped the action while the rename business implementation remained present.

## Identity architecture retained from alpha46/alpha47

- Explicit `POST /backend-api/conversation/init` request-body `conversation_id` is the validated foreground existing-chat identity signal. Generic/background traffic is passive.
- `CEConversationContext` remains the sole long-lived active conversation identity owner.
- Arbitrary UUID-looking UIKit/menu/config identifiers and titles are never execution authority.
- Current top-right chat menu freezes an immutable exact ID for current-conversation actions; action cancels if exact context changes before execution.
- Share remains validation-only and must never be silently invoked for identity discovery.
- Old conversation-tool floating UI stays retired. Percentage UI is separate and untouched.

## Alpha48 status

- Candidate `0.1.0-alpha48-reload-ui-title`; Actions `32973529739`, job `98192604072`; package id `9608529953`, dylib id `9608530563`.
- Validation: **Code written → CI passed → Artifact produced → Runtime/manual partially tested and NOT accepted.**

## Required alpha49 real-device acceptance

1. Current top-right menu contains enhancer `重命名会话` again.
2. Rename changes only the immutable exact current conversation; switching context before confirmation must cancel rather than rename another chat.
3. Pull / Reload / Export exact targeting remains unchanged and no cross-conversation behavior appears.
4. Project chat title is replaced only if the real host header surface is found; gear marker appears left of the synthetic display title; synthetic title never affects identity.
5. Reload baseline becomes provable on the actual conversation content window and a visibly refreshed page can satisfy UI rebuild proof. Request-only must still remain unconfirmed.
6. If the active host still renders header/message content through a surface not reached by public UIKit traversal, record that as runtime evidence; do not add private-class guesses or timers.
7. Generation stuck/recovery behavior is not an alpha49 acceptance item beyond ensuring no regression.

## Rejected / do-not-repeat

- request observed == Reload completed;
- page/UI rebuilt == interrupted generation recovered;
- speculative resume/retry/watchdog without runtime evidence;
- generic latest-request foreground authority;
- arbitrary UUID-shaped UI/config identifiers as conversation IDs;
- title-only execution target;
- stale-ID fallback;
- silently invoking Share/create to discover ID;
- second long-lived conversation authority;
- periodic UI-title identity timer;
- private Swift class hard-coding;
- History/sidebar/UIKit navigation fallback or alternate conversation ID;
- enhancer-generated title as identity evidence;
- restoring alpha46 `CECandidatesForSourceView(...)` as current-conversation execution authority;
- touching percentage-owned files in this work.

## Next exact action

Implement alpha49 minimal source changes on `feat/conversation-recognition`, synchronize version/package/workflow identity, run isolated CI, then update this checkpoint and durable docs with exact commit/run/artifact evidence. Runtime remains pending until the user tests the exact alpha49 artifact.