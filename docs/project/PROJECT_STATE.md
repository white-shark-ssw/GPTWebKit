# Project State

_Last updated: 2026-08-27._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- Product base `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` is the newest recognition branch. No recognition candidate is Stable/Frozen.

## Current development candidate

### ChatGPTEnhancer `0.1.0-alpha52-sync-refresh-handoff`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `9c06219cdee1ac00b75372f1480278169b3f6e59`; CI bookkeeping `087d03884b6a4c565d126e8c90849bafa0bf28e9`; post-CI cleanup head `90c5bb97f332b2c0c4935ad3eaea9432df3e156e`.
- CI passed: Actions `33004675627`, job `98295074960`.
- Artifacts: package id `9620028731`, digest `sha256:7fa4de42d8276e66934b4d4b2551ddf0f0916a069446388a6af4ae657140c075`; dylib id `9620029383`, Actions archive digest `sha256:dc87efcc450d5b26a9588606999cea1c481ff7ac33da51d57a88da47eea198ae`.
- Extracted dylib: arm64 Mach-O, 593616 bytes, sha256 `0b19bb2ec6d2b9a5ff26210bbd8d8945cffa77bb280b38e28ef1e0f9dc7f62d5`.
- Status: **Code written → CI passed → Artifact produced. Runtime/manual pending.**

## Alpha52 behavior

- Current action remains `同步最新消息`; alpha51's exact-ID guard, concurrent-Sync guard and terminal HTTP 429 behavior remain unchanged.
- Manual current-page handoff now says **`正在请求客户端刷新当前会话…`**, not `正在重载当前会话…`; route delivery alone is explicitly not treated as a visible reload.
- If same-ID request delivery **and** UI rebuild are both observed, success is `✓ 当前会话页面已刷新`.
- If same-ID request delivery occurs but no UI rebuild follows, alpha52 ends with `已请求客户端刷新，但页面未发生刷新。`.
- Once same-ID request delivery is proven, alpha52 stops sending further exact-route attempts merely because UI did not change. Alternate same-ID route delivery is retained only when the previous delivery produced no same-ID request evidence at all.
- No new visible-refresh mechanism is guessed in alpha52; no `/resume`, watchdog, alternate ID, History/sidebar/UIKit navigation fallback, Catalog throttling, project-header change or percentage change was added.

## Authoritative alpha51 runtime finding retained

Trace `conversation-identity-60CF506D-C2A9-4E8A-8A96-B01E1FD8FD70.log`, app `1.2026.202`, exact target `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7 / 优化会话识别v1`:

- Sync reached the finished-result → Reload handoff for the correct exact ID.
- Three custom-route deliveries produced only three same-ID conversation-detail GETs; there were zero `conversation/init`, zero `/prepare`, zero `/resume`, and all 20 UI verifier samples remained `uiRebuildObserved=NO` / `uiSawDisappear=NO`.
- User independently saw no page refresh. Therefore same-ID request/openURL delivery is not a host UI reload mechanism by itself.
- That trace contained no HTTP 429, so alpha51/52 terminal 429 behavior remains runtime-unexercised.

## Existing architecture / contracts

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole active-conversation identity authority.
3. `CENetworkObserver` — passive host-network observation; only validated explicit `POST /backend-api/conversation/init` body ID may promote foreground identity.
4. `CEAPIClient` — sole enhancer-originated ChatGPT request owner; HTTP 429 is terminal for the current request rather than a burst-retry trigger.
5. `CECatalog` — conversation catalog/title state.
6. `CEEnhancerUI` — current exact-ID menu integration and row-scoped sidebar Rename/Export.
7. `CEConversationUIReloadEvidence` — ephemeral UI refresh/rebuild proof, never identity authority.
8. `CEConversationIdentityTrace` — optional sanitized runtime evidence, never identity authority.

## Other retained runtime findings

- Alpha50 project-header trace proved exact identity/title acquisition but rejected the current UIKit `聊天 UILabel + nearby title UILabel` target on app `1.2026.202`; user has paused this feature.
- Reload request delivery is not Reload completion, and UI rebuild is not proof that an interrupted generation stream recovered.
- Sidebar Rename/Export selected-row acceptance and duplicate-title behavior remain pending real-device verification.

## Parallel task

- `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43.
- Alpha52 did not modify percentage-owned source/checkpoint.

## Next evidence

- Alpha52 needs device verification that truthful messages appear and a delivered same-ID refresh request no longer turns into the previous three-request burst.
- Before implementing a new genuine host refresh/rebuild mechanism, capture one sanitized **A → B → A normal navigation** trace with Sync/Reload untouched during the sequence. Compare that known genuine host navigation/rebuild traffic with the failed same-conversation custom-route path.
- This diagnostic sequence does not authorize History/sidebar navigation as the production Reload implementation.
- A broader Catalog traffic change still requires internal request-count/status evidence.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.