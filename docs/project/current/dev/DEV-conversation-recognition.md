# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；侧栏 Rename / Export 保持被长按行作用域；继续完善 Sync/Reload 的真实完成语义。项目顶部标题按用户要求暂停。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。服务器 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；只有真实 UI refresh/rebuild 才能报告可见同步/重载完成。

## Resume identity / conflict guard — 2026-08-27

- **Baseline**: `feat/chatgpt-enhancer-v0.1` = `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked unchanged before alpha52.
- **Working branch / PR**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; PR rechecked open/draft/mergeable before implementation.
- **Parallel task**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Alpha52 did not touch percentage-owned files/checkpoint.
- **Candidate uniqueness**: `ENH-0.1.0-alpha52-sync-refresh-handoff` / `0.1.0-alpha52-sync-refresh-handoff` was allocated uniquely after checking BUILD_TEST_INDEX and the parallel checkpoint.
- **No Frozen conflict**: product modules remain Active; alpha52 changes only recognition Feature/version/CI files and does not change `CEConversationContext` ownership.

## Authoritative alpha51 runtime evidence

Trace `conversation-identity-60CF506D-C2A9-4E8A-8A96-B01E1FD8FD70.log`, app `1.2026.202`, exact target `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7 / 优化会话识别v1`:

- Sync exact target remained correct and entered Reload after about 9.029s, so the finished-result gate executed for the same ID.
- Reload route attempts 0/1/2 all returned `opened=YES`, but produced only three same-ID detail GETs at roughly +0.034s, +2.978s and +5.938s.
- During the observed Reload interval: zero `conversation/init`, zero `/prepare`, zero `/resume`, and 20 verifier samples with `uiRebuildObserved=NO` / `uiSawDisappear=NO`.
- User independently reported no visible page change. Therefore same-ID route/request delivery can occur without a visible page rebuild.
- `正在重载当前会话…` was misleading in that failure mode, and the repeated route deliveries increased short-window request volume without demonstrated UI benefit.
- This trace contained no HTTP 429, so alpha51/52 terminal 429 behavior remains runtime-unexercised.

## Current candidate — alpha52

- **Candidate**: `ENH-0.1.0-alpha52-sync-refresh-handoff` / `0.1.0-alpha52-sync-refresh-handoff`.
- **Source baseline**: alpha51 post-CI head `8722e5f2a0a7bd6513997825b1a25991e5d342b7`.
- **Build/test source**: `9c06219cdee1ac00b75372f1480278169b3f6e59`.
- **Actions**: run `33004675627`, job `98295074960` — completed **success**. Checkout, run-id bookkeeping, Xcode check, Build, package upload and dylib upload all passed.
- **CI bookkeeping**: `087d03884b6a4c565d126e8c90849bafa0bf28e9`.
- **Post-CI cleanup/current branch head**: `90c5bb97f332b2c0c4935ad3eaea9432df3e156e`.
- **Post-CI compare**: tested source → current head changes only `.github/latest-enhancer-run-id` and removal of the temporary recognition-branch workflow trigger; tested product source is unchanged.
- **Artifacts**:
  - package `ChatGPTEnhancer-0.1.0-alpha52-sync-refresh-handoff`, id `9620028731`, digest `sha256:7fa4de42d8276e66934b4d4b2551ddf0f0916a069446388a6af4ae657140c075`;
  - dylib `ChatGPTEnhancer-0.1.0-alpha52-sync-refresh-handoff-dylib`, id `9620029383`, Actions archive digest `sha256:dc87efcc450d5b26a9588606999cea1c481ff7ac33da51d57a88da47eea198ae`;
  - extracted `ChatGPTEnhancer.dylib`: arm64 Mach-O, 593616 bytes, sha256 `0b19bb2ec6d2b9a5ff26210bbd8d8945cffa77bb280b38e28ef1e0f9dc7f62d5`.
- **Validation state**: **Code written → CI passed → Artifact produced. Runtime/manual/real-device: Pending.** Nothing Stable/Frozen.

## Alpha52 implementation

1. `CEManualReloadConversationID(...)` no longer tells the user a visible reload has begun. Start state is now **`正在请求客户端刷新当前会话…`**.
2. When exact same-ID request delivery and UI rebuild are both proven, final success is **`✓ 当前会话页面已刷新`**.
3. When a same-ID request is proven but no UI rebuild appears, the operation ends with **`已请求客户端刷新，但页面未发生刷新。`**.
4. After same-ID request delivery is proven, alpha52 **suppresses further exact-route delivery**. It continues observing the existing UI-proof window but does not send route attempt 1/2 merely because the UI has not changed.
5. Alternate exact-current route delivery remains available only when the previous route produced **no** same-ID request evidence at all. This preserves delivery fallback without repeating requests after delivery is already proven.
6. Existing exact-ID guards, app-state/context-change cancellation, UI rebuild proof, alpha51 HTTP 429 terminal handling, stale-stream safety, sidebar Rename/Export and menu identity behavior remain unchanged.
7. No `/resume`, new timer/watchdog family, alternate ID, History/sidebar/UIKit navigation, Catalog throttling, project-header change or percentage change was added.

## Data requirement for the real visible-refresh solution

- The alpha51 trace was sufficient to implement alpha52's immediate safety/wording corrections; no additional data was required before coding alpha52.
- **Additional runtime evidence is still required before implementing a new host-side refresh/rebuild mechanism.** Alpha52 intentionally does not guess one.
- Preferred targeted capture with the alpha52 artifact:
  1. start `会话识别记录`;
  2. while conversation A is visible, switch normally to conversation B and then back to A so the official app performs a known genuine navigation/rebuild;
  3. do not press Sync or Reload during this A→B→A sequence;
  4. end/export the trace and send it back.
- This A→B→A sequence is **diagnostic evidence only**. It does not authorize History/sidebar navigation as the production Reload implementation. We compare genuine host navigation/rebuild traffic with the failed same-conversation custom-route path before deciding the next code change.

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

Give the exact alpha52 artifact to the user. Real-device acceptance should verify truthful messages and that one delivered same-ID refresh request no longer causes the previous three-request burst. Then obtain one sanitized A→B→A trace to identify evidence for a genuine host rebuild path before attempting another visible-sync mechanism.