# Project State

_Last updated: 2026-08-27._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- `feat/chatgpt-enhancer-v0.1` remains the product base at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` remains the newest recognition branch. No recognition candidate is Stable/Frozen.

## Current development candidate

### ChatGPTEnhancer `0.1.0-alpha50-sidebar-menu-actions`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `44b7baf84458c19c963ce0a7ee0d869da28dfe08`; Actions bookkeeping `7988e2c06c38c419885f815e4960a892c08fe28f`; post-CI branch head `a52f4d0bd5406a61fc7c43e9cbae788f8dae43ac`.
- CI passed: Actions `32984372907`, job `98228416235`.
- Artifacts: package id `9612825155`; dylib id `9612825334`.
- Validation: **Code written → CI passed → Artifact produced → Runtime/manual partially tested.**

## Runtime findings

### Exact-current/menu architecture

- Current top-right menu actions use the immutable exact conversation ID proven by explicit `POST /backend-api/conversation/init` body `conversation_id` and fail closed if current context changes.
- Alpha49 device feedback confirmed the current top-right custom menu is present and usable. Alpha50 restores only sidebar/non-current `重命名会话` + `导出 Markdown`; selected-row runtime acceptance remains pending.

### Project header — paused

- Alpha50 trace `A3EA89F2-CE1A-48B9-A0FB-06C7E8A9FAE9` proves the final current chat exactly as `6a8d9489-31e8-83ec-ad29-343a6b883e6d / 会话百分比v1` and proves title acquisition is correct.
- The visible project header still does not change. Actual project-chat windows expose zero matching top UIKit `UILabel`s and zero `HEADER-TARGET`; the current `聊天 UILabel + nearby title UILabel` strategy is runtime-rejected on app `1.2026.202`.
- User explicitly asks to pause this header problem for now. Do not continue the UILabel route or allocate work for it until requested.

### Pull Latest rate limiting

- User frequently sees `请求频率受限，正在重试 1/3…` when using `拉取最新消息`.
- Source inspection proves this message is emitted only when `CEAPIClient` receives **HTTP 429**. Manual Pull issues `GET /backend-api/conversation/<exact-current-id>` and forwards API-client retry progress directly to UI.
- Current generic API-client policy automatically retries 429 up to three times after the first request using short delays (`0.7 / 1.5 / 3.0s`) unless numeric `Retry-After` is supplied; even then the delay is capped at 10 seconds. This can amplify a server rate limit instead of reducing request pressure.
- `CECatalog` can also generate substantial enhancer-originated background request volume by paging global conversations and known project conversations. This is a source-proven potential contributor, but current identity traces intentionally exclude enhancer-internal requests, so a specific user's 429 cannot yet be attributed to catalog traffic without sanitized internal request/status evidence.
- Current Pull fetch is not a full UI refresh: it checks/analyzes server conversation state and may cancel stale tracked stream tasks, but its internal response is not directly applied to the current page. Product semantics should be revisited before calling it a true “pull latest messages” UI refresh.

## Current architecture / contracts

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole active-conversation authority.
3. `CENetworkObserver` — passive host-network observation; only validated explicit `conversation/init` body ID may promote foreground identity.
4. `CEAPIClient` — sole enhancer-originated request owner.
5. `CECatalog` — conversation catalog/title state.
6. `CEEnhancerUI` — host menu/UI integration; current project-header UILabel mutation path is runtime-rejected on the tested host build.
7. `CEConversationUIReloadEvidence` — ephemeral Reload UI proof.
8. `CEConversationIdentityTrace` — optional sanitized runtime evidence, never identity authority.

## Parallel task

- `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43.
- Current recognition work does not modify percentage-owned source/checkpoint.

## Known issues / next evidence

- Pull Latest 429 handling should be changed only after user asks to proceed. Minimal direction: do not burst-retry 429 for manual Pull; report server rate-limit information accurately.
- A broader catalog-traffic reduction requires runtime internal request-count/status evidence before attribution is treated as fact.
- Reload UI-proof and interrupted-generation recovery remain separate pending issues.
- Project-header presentation is paused by user.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.