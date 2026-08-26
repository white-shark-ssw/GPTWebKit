# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 会话，并确保当前会话 Sync / Reload / Export / Rename 不串会话；保留侧栏会话行安全 Rename / Export，并继续完善同步/重载语义。项目顶部标题展示当前按用户要求暂停。
- **Acceptance invariant**: 当前会话 Sync / Reload / Export / Rename 必须使用真实当前 conversation ID，不得串会话；同名会话必须可精确区分。侧栏 Rename / Export 必须作用于被长按行。429 不得由插件短间隔自动重试放大。同步成功必须最终反映到当前会话页面，不能只代表服务器 JSON 请求成功。Reload 请求发生不等于 Reload 完成。插件生成标题只能用于 presentation，不能成为 identity evidence。

## Resume identity / conflict guard — 2026-08-27

- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked unchanged before alpha51 work.
- **Working branch / PR**: `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; current branch rechecked at `8722e5f2a0a7bd6513997825b1a25991e5d342b7`; PR rechecked open/draft/mergeable at the same head.
- **Parallel task**: only other Active checkpoint is `DEV-conversation-usage`, branch `feat/conversation-usage` at rechecked head `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Percentage-owned files/checkpoint were not modified.
- **Candidate uniqueness**: alpha43 and recognition alpha42–50 were already allocated. `ENH-0.1.0-alpha51-sync-latest-rate-limit` / product `0.1.0-alpha51-sync-latest-rate-limit` is unique.

## Authoritative alpha50 runtime/source evidence

### Project title — paused

Trace `conversation-identity-A3EA89F2-CE1A-48B9-A0FB-06C7E8A9FAE9.log`, app `1.2026.202`, proves exact final chat `6a8d9489-31e8-83ec-ad29-343a6b883e6d / 会话百分比v1` while the current UIKit `UILabel` header strategy fails. User explicitly asked to stop working on this issue for now. Alpha51 does not modify it.

### Pull Latest / 429

- User frequently saw `请求频率受限，正在重试 1/3…` from the former `拉取最新消息` action.
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
  - dylib `ChatGPTEnhancer-0.1.0-alpha51-sync-latest-rate-limit-dylib`, id `9618537770`, Actions archive digest `sha256:fd94fc813723cdef6067930e4a512da3155f2e6f78bae6c0ea0d3ec7e0385e16`;
  - extracted dylib: arm64 Mach-O, 593456 bytes, sha256 `2ccc4108373b5ede6c14bfba5057ceed08354b53b934ea493ae5e413e4be3ccf`.
- **Validation state**: **Code written → CI passed → Artifact produced → Runtime/manual partially tested. Alpha51 visible Sync handoff is NOT accepted.** Nothing Stable/Frozen.

## Alpha51 implementation

1. Current top-right menu label is **`同步最新消息`**. Existing compatibility method names/identifier are retained; no identity route changed.
2. Manual Sync still starts from the immutable exact current conversation ID. `CEFeatures` records `ACTION-SYNC`; the target is checked at action entry, after the asynchronous GET, and again immediately before handing off to Reload.
3. A short-lived manual Sync in-flight guard prevents repeated taps from creating concurrent Sync GETs. It is operation state only and never conversation identity authority.
4. `CEAPIClient` no longer automatically retries **HTTP 429**. A 429 now ends the current request. Numeric `Retry-After` is shown as `请求频率受限，请 N 秒后再试。`; otherwise the message is `请求频率受限，请稍后再试。`. Existing transport/5xx/auth retry behavior is otherwise unchanged.
5. Sync issues one enhancer `GET /backend-api/conversation/<exact-current-id>` and analyzes the latest server node. If the server says the latest assistant turn is still active, Sync reports `服务端仍在生成中，暂未刷新页面。` and does not cancel/reload the live stream.
6. If the server latest result is finished and the exact current ID is still unchanged, Sync keeps the pre-existing stale-stream cancellation safety and then invokes the existing `CEManualReloadConversationID(exactID)` path.
7. Final page success remains governed by the existing Reload contract: exact same-ID official request **plus** UI refresh/rebuild proof. A successful Sync GET alone is not shown as final page synchronization success.
8. Alpha51 does not change Catalog paging, project-title code, percentage files, generation `/resume`, alternate-ID logic, or add a new retry/watchdog/timer family.

## Authoritative alpha51 runtime evidence — 2026-08-27

Trace `conversation-identity-60CF506D-C2A9-4E8A-8A96-B01E1FD8FD70.log`, enhancer `0.1.0-alpha51-sync-latest-rate-limit`, app `1.2026.202`:

- Sync target stayed exact and unchanged: `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7 / 优化会话识别v1`.
- `ACTION-SYNC` was recorded, and **9.029s later** alpha51 entered `ACTION-RELOAD`. Current source only reaches that handoff after the enhancer GET returned non-error 2xx/non-empty data, the exact context still matched, and `CERecoveryAnalyzeConversation(...).finished == YES`. The identity trace intentionally does not record the enhancer-internal GET status/body itself.
- Reload baseline was `baselineUI=unproven`. Route attempts `0`, `1`, and `2` all reported `opened=YES`.
- Those three route deliveries caused three host `GET /backend-api/conversation/<same exact ID>` requests at approximately `+0.034s`, `+2.978s`, and `+5.938s` after Reload started.
- The trace contains **zero** `conversation/init`, **zero** `/prepare`, and **zero** `/resume` requests during this Reload sequence.
- Across 20 recorded Reload verifier samples before the user ended the trace, `uiRebuildObserved=NO` every time and `uiSawDisappear=NO`; the user independently reports that the page showed no visible change.
- Therefore this is not merely the earlier alpha48 UI-proof false-negative case: in this alpha51 run, user observation and plugin evidence agree that the current same-conversation custom-route handoff did **not** produce a visible page rebuild/refresh.
- The user-facing `正在重载当前会话…` message is therefore too strong if interpreted as evidence that a page Reload has begun; it only means the plugin entered its Reload attempt state.
- The three manual Reload route attempts also create repeated same-ID host GETs in a short window. They are **not** the removed `CEAPIClient` 429 automatic retries, and this trace contains no 429, but they still increase request volume and should not be repeated automatically when the first route has already delivered a same-ID detail request without UI effect.

### Runtime classification

- Exact conversation targeting: **passed for this trace**.
- Alpha51 `CEAPIClient` 429 behavior: **not exercised in this trace**; no 429 appeared.
- Sync server-state gate → Reload handoff: **executed**.
- Visible current-page synchronization: **failed / not accepted**.
- Current Reload custom-route attempts: **request delivery observed, UI reload not observed**.

## Architecture retained

- Only validated explicit `POST /backend-api/conversation/init` body `conversation_id` promotes foreground identity into sole `CEConversationContext`.
- Generic/background request recency, arbitrary menu/config UUIDs and title-only matching are not current-conversation authority.
- Current top-right menu freezes exact ID for Sync/Reload/Rename/Export and actions fail closed if current context changes.
- Sidebar Rename/Export are row-scoped catalog-candidate actions and never borrow/mutate active context.
- `CEAPIClient` remains the sole enhancer-originated ChatGPT request owner.
- Reload success still requires exact same-ID request delivery plus UI refresh/rebuild evidence.
- Official Share remains validation-only and is never invoked silently for identity.
- Percentage task remains separate and untouched.

## Required next acceptance / direction

1. Do not claim `同步最新消息` completed visible synchronization merely because it reached the manual Reload state.
2. User-facing handoff wording must distinguish `已获取服务器最新状态 / 正在请求客户端刷新` from a proven page Reload.
3. Before another candidate, inspect the exact current manual Reload path with this trace as ground truth. The three same-ID custom-route attempts produced only detail GETs and no UI rebuild; do not add more route retries, timers, alternate IDs, sidebar/history navigation, or guessed `/resume` behavior.
4. If a minimal change proceeds, stop repeated route attempts once same-ID request delivery is already proven but UI remains unchanged, so Sync/Reload does not generate additional request bursts with no demonstrated benefit.
5. A real Sync implementation still needs evidence for a host-side refresh/rebuild mechanism that actually updates the visible current page. Until that evidence exists, fail honestly rather than report completion.
6. Current top-right Rename/Export, sidebar Rename/Export, exact identity, percentage isolation, and paused project-title scope remain unchanged.

## Rejected / do-not-repeat

- automatic burst-style retries after HTTP 429;
- treating `1/3` as an OpenAI quota display rather than plugin retry count;
- claiming server GET success means the page synchronized;
- claiming `openURL(...)=YES` or same-ID detail GET means the page reloaded;
- repeating the same custom-route delivery after request delivery is already proven when runtime evidence shows no UI effect;
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

Wait for the user to authorize the next code change. If authorized, keep the same `DEV-conversation-recognition` task, recheck branch/base/parallel/candidate uniqueness, allocate a new candidate, then make the smallest evidence-backed correction: truthful Sync/Reload handoff messaging and removal of repeated same-ID route attempts after request delivery is proven. Do not claim that alone solves visible synchronization; investigate a real host refresh/rebuild mechanism separately from the trace evidence.