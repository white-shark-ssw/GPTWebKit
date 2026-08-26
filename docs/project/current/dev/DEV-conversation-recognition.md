# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 会话，并确保当前会话 Sync / Reload / Export / Rename 不串会话；保留侧栏会话行安全 Rename / Export，并继续完善同步/重载语义。项目顶部标题展示当前按用户要求暂停。
- **Acceptance invariant**: 当前会话 Sync / Reload / Export / Rename 必须使用真实当前 conversation ID，不得串会话；同名会话必须可精确区分。侧栏 Rename / Export 必须作用于被长按行。429 不得由插件短间隔自动重试放大。同步成功必须最终反映到当前会话页面，不能只代表服务器 JSON 请求成功。Reload 请求发生不等于 Reload 完成。插件生成标题只能用于 presentation，不能成为 identity evidence。

## Resume identity / conflict guard — 2026-08-27

- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked unchanged before alpha51 work.
- **Working branch / PR**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; PR rechecked open/draft/mergeable before implementation.
- **Parallel task**: only other Active checkpoint is `DEV-conversation-usage`, branch `feat/conversation-usage` at rechecked head `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Percentage-owned files/checkpoint were not modified.
- **Candidate uniqueness**: alpha43 and recognition alpha42–50 were already allocated. `ENH-0.1.0-alpha51-sync-latest-rate-limit` / product `0.1.0-alpha51-sync-latest-rate-limit` is unique.

## Authoritative alpha50 runtime/source evidence

### Project title — paused

Trace `conversation-identity-A3EA89F2-CE1A-48B9-A0FB-06C7E8A9FAE9.log`, app `1.2026.202`, proves exact final chat `6a8d9489-31e8-83ec-ad29-343a6b883e6d / 会话百分比v1` while the current UIKit `UILabel` header strategy fails. User explicitly asked to stop working on this issue for now. Alpha51 does not modify it.

### Pull Latest / 429

- User frequently sees `请求频率受限，正在重试 1/3…` from the former `拉取最新消息` action.
- Source proves this message was emitted only after `CEAPIClient` received HTTP 429 from the enhancer-originated request.
- The old action sent `GET /backend-api/conversation/<exact-current-id>` and analyzed server state/stale streams, but did not cause the host current page to re-render that returned JSON.
- Old `CEAPIClient` retried HTTP 429 up to three additional times after the initial request using `0.7 / 1.5 / 3.0s`, or numeric `Retry-After` clamped to 10 seconds. Thus one user tap could create up to four requests after the server had already asked the client to slow down.
- HTTP 429 is server-side rate limiting. Short-window request bursts are a plausible trigger, and the former plugin retry policy could amplify them. Exact account/IP/endpoint thresholds remain undocumented and must not be guessed.
- `CECatalog` can also originate background requests, but no sanitized runtime evidence attributes a specific 429 to catalog volume. Alpha51 deliberately does not change Catalog paging.

## Current candidate — alpha51

- **Candidate**: `ENH-0.1.0-alpha51-sync-latest-rate-limit` / `0.1.0-alpha51-sync-latest-rate-limit`.
- **Source baseline**: alpha50 post-CI head `a52f4d0bd5406a61fc7c43e9cbae788f8dae43ac`.
- **Build/test source**: `bbc8696d7c11f2d6030d7e44cdc3c979f38dba77`.
- **Actions**: run `33000977913`, job `98282430781` — completed **success**; Checkout, run-id bookkeeping, Build, package upload and dylib upload all passed.
- **CI bookkeeping**: `798631ce879dd32e5f774659789d03c3772ad1f5`.
- **Post-CI cleanup/current branch head**: `8722e5f2a0a7bd6513997825b1a25991e5d342b7`. Compare from tested source changes only `.github/latest-enhancer-run-id` and removal of the temporary recognition-branch CI trigger; product source is unchanged.
- **Artifacts**:
  - package `ChatGPTEnhancer-0.1.0-alpha51-sync-latest-rate-limit`, id `9618537159`, digest `sha256:8b72320f471e540d679a4b79899659e43250c79543ce0a68b7bb76c70b6267cc`;
  - dylib `ChatGPTEnhancer-0.1.0-alpha51-sync-latest-rate-limit-dylib`, id `9618537770`, Actions archive digest `sha256:fd94fc813723cdef6067930e4a512da3155f2e6f78bae6c0ea0d3ec7e0385e16`.
  - extracted dylib: arm64 Mach-O, 593456 bytes, sha256 `2ccc4108373b5ede6c14bfba5057ceed08354b53b934ea493ae5e413e4be3ccf`.
- **Validation state**: **Code written → CI passed → Artifact produced. Runtime/manual/real-device: Pending.** Nothing Stable/Frozen.

## Alpha51 implementation

1. Current top-right menu label is now **`同步最新消息`**. Existing compatibility method names/identifier are retained; no identity route changed.
2. Manual Sync still starts from the immutable exact current conversation ID. `CEFeatures` records `ACTION-SYNC`; the target is checked at action entry, after the asynchronous GET, and again immediately before handing off to Reload.
3. A short-lived manual Sync in-flight guard prevents repeated taps from creating concurrent Sync GETs. It is operation state only and never conversation identity authority.
4. `CEAPIClient` no longer automatically retries **HTTP 429**. A 429 now ends the current request. Numeric `Retry-After` is shown as `请求频率受限，请 N 秒后再试。`; otherwise the message is `请求频率受限，请稍后再试。`. Existing transport/5xx/auth retry behavior is otherwise unchanged.
5. Sync issues one enhancer `GET /backend-api/conversation/<exact-current-id>` and analyzes the latest server node. If the server says the latest assistant turn is still active, Sync reports `服务端仍在生成中，暂未刷新页面。` and does not cancel/reload the live stream.
6. If the server latest result is finished and the exact current ID is still unchanged, Sync keeps the pre-existing stale-stream cancellation safety and then invokes the existing `CEManualReloadConversationID(exactID)` path. This causes the official host page to refetch/rebuild rather than claiming success from the plugin JSON GET alone.
7. Final page success remains governed by the existing Reload contract: exact same-ID official request **plus** UI refresh/rebuild proof. A successful Sync GET alone is not shown as final page synchronization success.
8. Alpha51 does not change Catalog paging, project-title code, percentage files, generation `/resume`, alternate-ID logic, or add a new retry/watchdog/timer family.

## Architecture retained

- Only validated explicit `POST /backend-api/conversation/init` body `conversation_id` promotes foreground identity into sole `CEConversationContext`.
- Generic/background request recency, arbitrary menu/config UUIDs and title-only matching are not current-conversation authority.
- Current top-right menu freezes exact ID for Sync/Reload/Rename/Export and actions fail closed if current context changes.
- Sidebar Rename/Export are row-scoped catalog-candidate actions and never borrow/mutate active context.
- `CEAPIClient` remains the sole enhancer-originated ChatGPT request owner.
- Reload success still requires exact same-ID request delivery plus UI refresh/rebuild evidence.
- Official Share remains validation-only and is never invoked silently for identity.
- Percentage task remains separate and untouched.

## Required alpha51 real-device acceptance

1. Current top-right menu shows `同步最新消息`, not `拉取最新消息`.
2. A single Sync tap produces one enhancer GET attempt; HTTP 429 must not trigger plugin `1/3`, `2/3`, `3/3` rate-limit retries.
3. If 429 includes numeric `Retry-After`, the user-facing error reports the wait seconds; otherwise it says to retry later.
4. Repeated taps while the first Sync request is in flight do not create concurrent enhancer Sync GETs.
5. If exact current conversation changes before GET completion or before Reload handoff, Sync cancels and must not refresh/cancel streams for the old target.
6. If server latest state is finished, Sync proceeds into exact-current page Reload; only the existing request+UI proof may report final Reload success.
7. If server says generation is still active, Sync reports that state and does not force Reload/cancel a live stream.
8. Current top-right Reload/Rename/Export and sidebar Rename/Export behavior remain unchanged.

## Rejected / do-not-repeat

- automatic burst-style retries after HTTP 429;
- treating `1/3` as an OpenAI quota display rather than plugin retry count;
- claiming server GET success means the page synchronized;
- changing Catalog paging without request-count/status evidence;
- current/header title text as identity evidence;
- continuing the rejected UIKit UILabel-pair header strategy in this candidate;
- generic latest-request foreground authority or stale-ID fallback;
- sidebar actions borrowing current `CEConversationContext`;
- request observed == Reload completed;
- page rebuilt == interrupted generation recovered;
- speculative `/resume`, watchdog or generation retry;
- second long-lived conversation authority;
- touching percentage-owned files.

## Next exact action

Hand the exact alpha51 artifact to the user and perform real-device acceptance focused on Sync: menu wording, one-request/no-429-retry behavior, repeated-tap guard, same-ID cancellation, finished-result → exact Reload handoff, and live-generation no-forced-refresh behavior. Record the runtime result before any further rate-limit or Catalog changes.