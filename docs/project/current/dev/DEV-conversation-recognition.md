# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；侧栏 Rename / Export 保持被长按行作用域；继续完善 Sync/Reload 的真实完成语义。项目顶部标题按用户要求暂停。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。服务器 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；只有真实 UI refresh/rebuild 才能报告可见同步/重载完成。

## Resume identity / conflict guard — 2026-08-27

- **Baseline**: `feat/chatgpt-enhancer-v0.1` = `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked unchanged.
- **Working branch / PR**: `feat/conversation-recognition` = `8722e5f2a0a7bd6513997825b1a25991e5d342b7`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; PR rechecked open/draft/mergeable at the same head.
- **Parallel task**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Alpha52 does not touch its percentage-owned files/checkpoint.
- **Candidate uniqueness**: BUILD_TEST_INDEX contains recognition alpha42–51 and parallel alpha43. New candidate allocated: `ENH-0.1.0-alpha52-sync-refresh-handoff` / product `0.1.0-alpha52-sync-refresh-handoff`; unique at allocation.
- **Module conflict**: alpha52 touches recognition-owned Feature/version/CI files only; no Frozen module exists. `CEConversationContext` ownership and identity rules remain unchanged.

## Previous candidate — alpha51

- **Candidate**: `ENH-0.1.0-alpha51-sync-latest-rate-limit` / `0.1.0-alpha51-sync-latest-rate-limit`.
- **Build/test source**: `bbc8696d7c11f2d6030d7e44cdc3c979f38dba77`.
- **Actions**: run `33000977913`, job `98282430781` — success.
- **Post-CI head**: `8722e5f2a0a7bd6513997825b1a25991e5d342b7`; product source unchanged after run-id bookkeeping/trigger cleanup.
- **Artifacts**: package id `9618537159`; dylib id `9618537770`; extracted dylib sha256 `2ccc4108373b5ede6c14bfba5057ceed08354b53b934ea493ae5e413e4be3ccf`.
- **Validation**: Code written → CI passed → Artifact produced → Runtime/manual partially tested. Nothing Stable/Frozen.

## Authoritative alpha51 runtime evidence

Trace `conversation-identity-60CF506D-C2A9-4E8A-8A96-B01E1FD8FD70.log`, app `1.2026.202`, exact target `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7 / 优化会话识别v1`:

- Sync exact target remained correct and transitioned to Reload after about 9.029s, meaning the alpha51 finished-result gate executed for the same ID.
- Reload baseline was `unproven`; route attempts 0/1/2 all returned `opened=YES`.
- Those three deliveries produced only three same-ID conversation-detail GETs at roughly +0.034s, +2.978s and +5.938s.
- During the observed Reload interval: zero `conversation/init`, zero `/prepare`, zero `/resume`, 20 verifier samples with `uiRebuildObserved=NO` and `uiSawDisappear=NO`.
- User independently reports no visible page change. Therefore this run proves the same-conversation custom route can deliver a request without rebuilding the visible page.
- `正在重载当前会话…` is misleading in this failure mode: it only means the plugin entered its Reload attempt state.
- The three route attempts are not CEAPIClient 429 retries and this trace contains no 429, but they add short-window request volume without demonstrated UI benefit.
- Alpha51 429 terminal behavior was not exercised by this trace; keep that result separate.

## Current candidate — alpha52

- **Candidate**: `ENH-0.1.0-alpha52-sync-refresh-handoff` / `0.1.0-alpha52-sync-refresh-handoff`.
- **Source baseline**: alpha51 post-CI head `8722e5f2a0a7bd6513997825b1a25991e5d342b7`.
- **User authorization**: continue development after alpha51 runtime failure; user asks whether more data is required.
- **Evidence-backed scope**:
  1. change Reload/Sync handoff wording so it says the plugin is **requesting client refresh**, not that a visible reload already began;
  2. if a same-ID request has already been observed and UI did not rebuild, stop that Reload attempt instead of automatically sending another same-ID route;
  3. alternate exact-current route delivery may only be attempted when prior route delivery produced **no** same-ID request evidence; it must not be used after delivery is proven;
  4. keep existing exact-ID safety, UI proof, 429 terminal behavior, stale-stream guard and sidebar behavior unchanged;
  5. do not add `/resume`, timers/watchdogs, alternate IDs, History/sidebar/UIKit navigation, Catalog throttling, project-header work or percentage changes.
- **Expected validation**: this candidate fixes truthful status and unnecessary repeated route requests. It does **not** claim to solve the missing host-side visible refresh mechanism.
- **Validation state**: candidate allocated; Code not yet written; CI/artifact/runtime pending.

## Data requirement for the real visible-refresh solution

- The current alpha51 trace is sufficient for alpha52's immediate corrections; no additional capture is required before implementing them.
- A **separate targeted runtime capture is still required** before implementing a new host-side refresh/rebuild mechanism. We need evidence from an action where the official app genuinely rebuilds/updates the visible current conversation, not another failed custom-route attempt.
- Preferred next evidence after alpha52: start the existing sanitized trace, perform a known genuine navigation/rebuild sequence such as A → B → A (without pressing Sync/Reload during the sequence), then export the trace. This is diagnostic evidence only; it does not authorize History/sidebar navigation as the production Reload mechanism.

## Architecture retained / rejected routes

- Sole active identity owner: `CEConversationContext`; only validated explicit `POST /backend-api/conversation/init` body `conversation_id` promotes foreground identity.
- Generic request recency, title-only matching and arbitrary UUIDs are not identity authority.
- Current menu freezes exact ID; sidebar Rename/Export remain row-scoped.
- `CEAPIClient` remains sole enhancer-originated request owner; 429 remains terminal for the current request.
- Do not claim GET/request/openURL success as UI Sync/Reload success.
- Do not automatically repeat same-route delivery once exact same-ID request delivery is proven but UI effect is absent.
- Do not add speculative `/resume`, generation retry, watchdog, alternate ID, History/sidebar/UIKit pop-push fallback, or a second state owner.
- Project-header work remains paused; percentage-owned files remain untouched.

## Next exact action

Implement alpha52 on `feat/conversation-recognition`: truthful Sync/Reload refresh-request messages and delivery-aware route retry suppression; synchronize version/build/workflow identity, run isolated CI, record artifacts, restore normal workflow trigger, and leave real visible-refresh mechanism pending targeted runtime evidence.