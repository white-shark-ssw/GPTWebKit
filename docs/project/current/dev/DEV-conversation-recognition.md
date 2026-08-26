# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 会话，并确保当前会话 Pull / Reload / Export / Rename 不串会话；保留侧栏会话行安全 Rename / Export，并继续完善 Pull/Reload 语义。项目顶部标题展示当前按用户要求暂停。
- **Acceptance invariant**: 当前会话 Pull / Reload / Export / Rename 必须使用真实当前 conversation ID，不得串会话；同名会话必须可精确区分。侧栏 Rename / Export 必须作用于被长按行。Reload 请求发生不等于 Reload 完成。插件生成标题只能用于 presentation，不能成为 identity evidence。

## Resume identity / conflict guard — 2026-08-27

- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked unchanged.
- **Working branch / PR**: `feat/conversation-recognition` at `a52f4d0bd5406a61fc7c43e9cbae788f8dae43ac`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; PR open/draft/mergeable.
- **Parallel task**: `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Percentage-owned source/checkpoint remains out of scope.
- **Current candidate**: `ENH-0.1.0-alpha50-sidebar-menu-actions` / `0.1.0-alpha50-sidebar-menu-actions`; unique vs parallel/historical candidates.

## Current candidate — alpha50

- **Build/test source**: `44b7baf84458c19c963ce0a7ee0d869da28dfe08`.
- **Actions**: run `32984372907`, job `98228416235` — success.
- **CI bookkeeping**: `7988e2c06c38c419885f815e4960a892c08fe28f`.
- **Post-CI branch head**: `a52f4d0bd5406a61fc7c43e9cbae788f8dae43ac`; product source unchanged from tested source after bookkeeping + feature-trigger cleanup.
- **Artifacts**: package id `9612825155`, digest `sha256:d19595daa76d7ecc1eb5432a68c6cf70ceb77912c094ac5aad0ecead45c5a983`; dylib id `9612825334`, digest `sha256:5580d466418c2e6ba7c6ad7eab46861e0efb8e65ca59b489a58e6356825ca8b7`.
- **Validation**: Code written → CI passed → Artifact produced → Runtime/manual partially tested. Nothing Stable/Frozen.

## Authoritative alpha50 runtime evidence

### Current-menu / project-title trace — 2026-08-27

Trace `conversation-identity-A3EA89F2-CE1A-48B9-A0FB-06C7E8A9FAE9.log`, app `1.2026.202`:

- final conversation is exactly `6a8d9489-31e8-83ec-ad29-343a6b883e6d / 会话百分比v1` from `conversation/init`, `IDENTITY-INIT`, prepare/detail and current-menu evidence;
- title acquisition is correct; project-header presentation still fails;
- actual project chat logs `topLabelCount=0` and zero `HEADER-TARGET`; current `聊天 UILabel + nearby title UILabel` strategy is runtime-rejected on this host build;
- top-right source is SwiftUI-hosted. Do not hard-code private class names. User now explicitly asks to **pause the top-title problem** and focus on Pull Latest.

### Pull Latest rate-limit report — 2026-08-27

- User frequently sees **`请求频率受限，正在重试 1/3…`** when using `拉取最新消息`.
- Current source proves this exact text can only come from `CEAPIClient.performMethod(...)` after the enhancer-originated request receives **HTTP 429**. `CEPullLatestConversationResult(...)` forwards the API-client progress text directly to the user.
- Current Pull implementation issues `GET /backend-api/conversation/<exact-current-id>` through `CEAPIClient`; the exact-current ID guard remains correct.
- `CEAPIClient` currently treats 429 as a generic automatic-retry condition: up to three retries after the first request. Default retry delays are `0.7s / 1.5s / 3.0s`; numeric `Retry-After` replaces the delay but is forcibly clamped to at most 10 seconds. A non-numeric HTTP-date `Retry-After` is not interpreted.
- Therefore `1/3` does **not** mean a local plugin quota. It means the server already returned 429 to the first Pull request, after which the plugin itself schedules another request. This retry behavior can prolong/amplify rate limiting instead of relieving it.
- Current `CECatalog` is also capable of significant enhancer-originated background request volume: `start/refreshIfPossible` fetches global conversation pages up to offset 5000 and known project pages up to 60 pages/project, and template changes may schedule another refresh subject to a 25-second last-refresh guard. These requests also use `CEAPIClient`. This is a **source-proven potential contributor**, but the current identity trace intentionally excludes enhancer-internal requests, so this trace does not prove how many such requests actually preceded a specific 429 on the user's device.
- The manual Pull response is analyzed for server completion and may cancel stale tracked stream tasks, but the fetched JSON is an enhancer-internal request and is intentionally not fed through `CENetworkObserver`/`CECatalog` ingestion. Pull does not directly replace/re-render the current page with that payload. Its current behavior is therefore closer to **server-state check / stale-stream recovery assistance** than a true UI data refresh.

## Current architecture retained

- Only validated explicit `POST /backend-api/conversation/init` body `conversation_id` promotes foreground identity into sole `CEConversationContext`.
- Generic/background request recency, arbitrary menu/config UUIDs and title-only matching are not current-conversation authority.
- Current top-right menu freezes exact ID for Pull/Reload/Rename/Export and actions fail closed if current context changes.
- Sidebar Rename/Export are row-scoped catalog-candidate actions and never borrow/mutate active context.
- `CEAPIClient` is the sole enhancer-originated ChatGPT request owner.
- Official Share remains validation-only and is never invoked silently for identity.
- Percentage task remains separate and untouched.

## Rejected / do-not-repeat

- current/header title text as identity evidence;
- continuing the rejected UIKit UILabel-pair header strategy without new public accessibility evidence;
- arbitrary UUID-shaped UI/config identifiers as conversation IDs;
- generic latest-request foreground authority;
- stale-ID fallback;
- sidebar actions borrowing current `CEConversationContext`;
- silently choosing duplicate-title sidebar records;
- request observed == Reload completed;
- page rebuilt == interrupted generation recovered;
- speculative `/resume`, watchdog or generation retry without runtime evidence;
- silently invoking Share/create for identity;
- second long-lived conversation authority;
- touching percentage-owned files in this work.

## Next exact action

Do **not** change the paused project-header feature. Explain the Pull Latest 429 behavior from current source. No new candidate is allocated yet. If the user asks to proceed with a fix, first recheck branch/base/parallel conflicts and candidate uniqueness, then prefer the smallest evidence-backed rate-limit change: stop burst-style automatic 429 retries for manual Pull and surface server rate-limit information accurately. Before making a broader `CECatalog` traffic change, add or obtain sanitized internal request-count/status evidence so request-volume attribution is proven rather than guessed. Also reassess whether the product should keep `拉取最新消息` as a server-state/recovery action or make its UI semantics explicit.