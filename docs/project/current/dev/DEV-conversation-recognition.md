# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 会话，并确保当前会话 Sync / Reload / Export / Rename 不串会话；保留侧栏会话行安全 Rename / Export，并继续完善同步/重载语义。项目顶部标题展示当前按用户要求暂停。
- **Acceptance invariant**: 当前会话 Sync / Reload / Export / Rename 必须使用真实当前 conversation ID，不得串会话；同名会话必须可精确区分。侧栏 Rename / Export 必须作用于被长按行。429 不得由插件短间隔自动重试放大。同步成功必须最终反映到当前会话页面，不能只代表服务器 JSON 请求成功。Reload 请求发生不等于 Reload 完成。插件生成标题只能用于 presentation，不能成为 identity evidence。

## Resume identity / conflict guard — 2026-08-27

- **Baseline**: `feat/chatgpt-enhancer-v0.1` at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`, rechecked unchanged immediately before alpha51 work.
- **Working branch / PR**: `feat/conversation-recognition` at `a52f4d0bd5406a61fc7c43e9cbae788f8dae43ac`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; PR rechecked open/draft/mergeable with same head.
- **Parallel task**: only other Active checkpoint is `DEV-conversation-usage`, branch `feat/conversation-usage` at rechecked head `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Its percentage-owned files remain out of scope. Shared `CEAPIClient` is a documented dependency, but alpha43 is idle/pending runtime and no current alpha51 edit touches percentage-owned source.
- **Candidate uniqueness**: alpha43 and recognition alpha42–50 are already allocated. `ENH-0.1.0-alpha51-sync-latest-rate-limit` / product `0.1.0-alpha51-sync-latest-rate-limit` is newly allocated and unique.

## Authoritative alpha50 runtime/source evidence

### Project title — paused

Trace `conversation-identity-A3EA89F2-CE1A-48B9-A0FB-06C7E8A9FAE9.log`, app `1.2026.202`, proves exact final chat `6a8d9489-31e8-83ec-ad29-343a6b883e6d / 会话百分比v1` while the current UIKit `UILabel` header strategy fails. User explicitly asked to stop working on this issue for now. Do not modify it in alpha51.

### Pull Latest / 429

- User frequently sees `请求频率受限，正在重试 1/3…` from the current `拉取最新消息` action.
- Source proves this message is emitted only after `CEAPIClient` receives HTTP 429 from the enhancer-originated request.
- Current action sends `GET /backend-api/conversation/<exact-current-id>` and then merely analyzes server state / stale streams; the returned JSON is not applied to the host current-page UI.
- Generic `CEAPIClient` currently retries HTTP 429 up to three additional times with short delays `0.7 / 1.5 / 3.0s`, or numeric `Retry-After` clamped to at most 10 seconds. One user tap can therefore create up to four requests after the server already asked the client to slow down.
- 429 is a server-side rate-limit response. Short-window request bursts are a plausible trigger and the plugin's own retry policy can amplify them; exact account/IP/endpoint quota policy remains undocumented and must not be guessed.
- `CECatalog` can also originate background requests, but no current sanitized evidence attributes a specific 429 to catalog volume. Do not broadly rewrite catalog traffic in this candidate.

## Current candidate — alpha51

- **Candidate**: `ENH-0.1.0-alpha51-sync-latest-rate-limit` / `0.1.0-alpha51-sync-latest-rate-limit`.
- **Source baseline**: alpha50 post-CI head `a52f4d0bd5406a61fc7c43e9cbae788f8dae43ac`.
- **User requirement**: rename the current-menu action from `拉取最新消息` to `同步最新消息`, and make the action a real current-page synchronization rather than a server-state-only check.
- **Planned minimal change**:
  1. user-facing menu/action messages become `同步最新消息` / `正在同步最新消息…`;
  2. keep the exact immutable current conversation ID guard at action entry and re-check the same ID when the asynchronous server request completes;
  3. add a short-lived in-flight guard so repeated taps cannot create concurrent sync requests; this state terminates on completion and is not conversation authority;
  4. stop automatic HTTP 429 retries in `CEAPIClient`; surface `Retry-After` seconds when provided, otherwise tell the user to retry later;
  5. on successful same-ID fetch, retain current stale-stream safety: if the server still reports active generation, do not force a page refresh; if the server reports a finished latest result, cancel stale tracked streams as before and then invoke the existing exact-current manual Reload path so the host page actually refetches/rebuilds. Final visible success remains governed by Reload's request+UI proof, not by the GET alone;
  6. do not change Catalog paging, paused project-title code, percentage files, generation `/resume`, retries/watchdogs/timers, or alternate-ID behavior.
- **Validation state**: candidate allocated; **Code not yet written** at this checkpoint. CI/artifact/runtime pending.

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
2. A single Sync tap produces at most one enhancer GET attempt; HTTP 429 does not trigger plugin `1/3`, `2/3`, `3/3` retries.
3. If 429 includes numeric `Retry-After`, user-facing error reports the wait seconds; otherwise it says to retry later.
4. Repeated taps while the first sync is still in flight do not create concurrent enhancer sync requests.
5. If the exact current conversation changes before the GET completes, Sync cancels and does not refresh/cancel streams for the old target.
6. If server latest state is finished, Sync proceeds into exact-current page reload and only reports final reload success if existing request+UI proof succeeds.
7. If server says generation is still active, Sync reports that state and does not force reload/cancel a live stream.
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

Implement alpha51 only in the current recognition branch: user-facing Sync wording, exact-ID async completion guard/in-flight guard, no automatic 429 retry with accurate Retry-After messaging, and successful finished-result handoff into existing exact-current Reload. Synchronize version/build/workflow identity, run isolated CI, record exact build/run/artifact evidence, restore the normal workflow trigger, and leave runtime acceptance pending until the user tests the exact artifact.