# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；侧栏 Rename / Export 保持被长按行作用域；继续完善 Sync/Reload 的真实完成语义。项目顶部标题按用户要求暂停。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。服务器 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；只有真实 UI refresh/rebuild 才能报告可见同步/重载完成。

## Resume identity / conflict guard — 2026-08-27

- Baseline `feat/chatgpt-enhancer-v0.1` rechecked unchanged at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Working branch `feat/conversation-recognition` rechecked at `f2478c58fcaaf621ccfdffb5cb0a08b89be8dc53`.
- Draft PR #2 → `feat/chatgpt-enhancer-v0.1` rechecked open/draft/mergeable with the same head/base.
- Parallel `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. This recognition session will not modify percentage-owned sources/checkpoint.
- No product module is Frozen. Diagnostics and Network are Active; touching `CENetworkObserver` is justified only to move diagnostic sampling to the already-existing NSURLSession task-creation hooks, without changing request ownership/production behavior.
- Candidate identities alpha42–53 and parallel alpha43 are already allocated. New unique diagnostic candidate is reserved as `ENH-0.1.0-alpha54-task-creation-trace` / `0.1.0-alpha54-task-creation-trace`.

## Authoritative alpha53 runtime evidence

Trace `conversation-identity-E076722C-E0F0-4044-8B99-41F727B1B62B.log`, enhancer `0.1.0-alpha53-refresh-path-trace`, app `1.2026.202`:

- Genuine A → B and B → A exact navigation both emitted exact `conversation/init`, then exact `prepare` + conversation detail within about 125 ms.
- Genuine exact init/prepare/detail snapshots showed `SwiftUI.UIKitNavigationController navCount=3`.
- Same-A `同步最新消息` → custom-route handoff produced one same-ID detail GET only, no exact init/prepare, no UI rebuild, and `navCount=1`.
- Alpha52 delivery-aware suppression was exercised successfully: after the first delivered same-ID request, there was no second/third route burst.
- All 11 alpha53 `REFRESH-PATH` call-stack signatures were identical across genuine navigation and failed same-current refresh. The current downstream logging point is therefore not upstream host-entry evidence.
- No HTTP 429 occurred in the capture.

## Previous candidate — alpha53

- Candidate `ENH-0.1.0-alpha53-refresh-path-trace` / `0.1.0-alpha53-refresh-path-trace`.
- Build/test source `b62878928816c40cbed8c11847a3ed7ae494adde`; Actions `33007145536`, job `98303728684` — success.
- Artifacts: package `9621009139`; dylib `9621009533`; extracted dylib sha256 `78a38421fe04adba9774bb8e42947ea48120d2a61698359f04c31bdb6f6f86a2`.
- Post-CI cleanup/current branch head `f2478c58fcaaf621ccfdffb5cb0a08b89be8dc53`.
- Validation: Code written → CI passed → Artifact produced → Runtime/manual/real-device partially tested. Production visible refresh remains unverified.

## Current candidate — alpha54 task-creation trace

- **Candidate**: `ENH-0.1.0-alpha54-task-creation-trace` / `0.1.0-alpha54-task-creation-trace`.
- **Source baseline**: alpha53 cleanup head `f2478c58fcaaf621ccfdffb5cb0a08b89be8dc53`.
- **Goal**: diagnostic-only refinement. Capture structural evidence earlier, at the existing NSURLSession task-creation hooks, and include the navigation-controller stack composition plus ID-less init/prepare staging that precedes genuine exact navigation.
- **Planned instrumentation only**:
  1. add a trace entry invoked directly from existing `dataTask...` / `uploadTask...` creation hooks before the common observer path;
  2. classify exact init, ID-less init staging, exact prepare, ID-less prepare staging, and exact conversation-detail GET;
  3. record hook source, bounded sanitized caller symbols, public navigation-controller stack class composition/count/visible controller, and structural target ID when present;
  4. keep persistence inside the existing user-started trace and retain the current sensitive-data prohibitions.
- **Do not add**: production refresh/navigation mutation, manual init/prepare replay, forced nav-stack restoration, UIKit pop/push, History/sidebar navigation, alternate IDs, `/resume`, watchdog/timer retry family, Catalog throttling, project-header work, or percentage changes.
- **Validation state**: candidate allocated; Code not yet written; CI/artifact/runtime pending.

## Architecture retained / rejected routes

- `CEConversationContext` remains sole active identity authority; only validated explicit exact `conversation/init` body ID promotes foreground identity.
- `CEAPIClient` remains sole enhancer-originated request owner. Diagnostic hooks observe only; they do not originate traffic.
- Server GET/request delivery is not visible Sync/Reload completion.
- Genuine init→prepare→detail and `navCount=3` are evidence of host state, not instructions to replay requests or mutate navigation stacks.
- Project-header work remains paused; percentage task remains untouched.

## Next exact action

Implement alpha54 diagnostic-only task-creation/staging/navigation-stack instrumentation on `feat/conversation-recognition`, synchronize candidate identity, run isolated CI/artifact, restore the normal CI trigger, then ask for one A → B → A → `同步最新消息` trace. Do not change production Sync/Reload behavior unless that trace exposes an evidence-backed host entry path.