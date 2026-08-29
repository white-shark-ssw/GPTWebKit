# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / 同步最新消息 / 重载 / conversation recognition / sync / reload`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；当前重点重新调查官方客户端“进入一个已完成会话 → 请求服务端 → 消费响应 → 刷新当前 UI”的真实链路，再基于该证据重做 Sync / Reload。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。插件自行 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；网络请求只有在官方 host 的真实响应消费/UI 更新链被证明后，才能作为 Sync/Reload 实现依据。

## Resume identity / conflict guard — 2026-08-30

- Baseline `feat/chatgpt-enhancer-v0.1` verified unchanged at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Working branch `feat/conversation-recognition`; Draft PR #2 remains open → `feat/chatgpt-enhancer-v0.1`.
- Parallel `DEV-conversation-usage` remains isolated on `feat/conversation-usage`, candidate alpha43. This task must not modify percentage-owned source/checkpoint.
- No product module is Frozen. Base did not materially advance. Branch / PR / base identities matched repository truth before alpha58 work started.

## Current candidate — alpha58

- Candidate ID: `ENH-0.1.0-alpha58-reentry-network-trace`.
- Product version: `0.1.0-alpha58-reentry-network-trace`.
- Build/test source: `c9f9c328386e63fd409421d74d7f18c091144ad2`.
- Actions: `33272953771`; job `99154630406` — **passed**.
- CI bookkeeping commit: `00b1aa85cb8d02d9b4e9be300a3f3c5bfa2296a2`.
- Post-CI cleanup head: `c0fa017e6bda0a4d91701e687abae3c8d51d3304`.
- Package artifact: `9720640754`, Actions digest `sha256:80dcb905eb95486208a9e0a3457050f15401c0d6ed2a2b85e0ca79f8434ac369`.
- Dylib artifact: `9720641009`, Actions digest `sha256:99deeeb00bc1cdf2779fcc349ab604ae1ddff7a957ea1d5d911adea77dd6de7a`.
- Extracted dylib: Mach-O 64-bit arm64, 615248 bytes, sha256 `df6c3f0b7e41b3386769f9df35d10dcb57bee4fee7e8c22c5190192dfd80a061`.
- Validation: **Code written → CI passed → Artifact produced → Runtime/manual partially tested.** Nothing Stable/Frozen.

## Authoritative alpha58 runtime evidence — trace E74DA953-6BB5-4A92-87DF-474142BD37C7

App `1.2026.202`, enhancer `0.1.0-alpha58-reentry-network-trace`.

1. A normal official entry into a finished target conversation emitted the exact sequence `POST /backend-api/conversation/init` → `POST /backend-api/f/conversation/prepare` → `GET /backend-api/conversation/<exact-id>`.
2. The exact init body contained only `conversation_id` and `timezone_offset_min`. The exact prepare body exposed the expected structural keys including `action`, `client_prepare_dispatch`, `client_prepare_source`, `conversation_id`, `model`, `parent_message_id`, buffering/encoding fields, timezone fields, and related flags; no raw values are persisted by the trace.
3. All three official requests were observed at `NSURLSessionTask resume` on the same public transport owner: opaque `session-1`, class `__NSURLSessionLocal`; the detail request was `task-12`, class `__NSCFLocalDataTask`.
4. The two tested Reload attempts did **not** reproduce the official sequence. Each route produced only one exact detail GET (`task-16`, then `task-17`) on the same `session-1`, with no exact init/prepare preceding it.
5. Both Reload attempts proved same-ID detail request delivery but produced no UI rebuild across the full verification window; each correctly ended with `requestObserved=YES`, `uiRebuildObserved=NO`.
6. Alpha58 did not capture a `NET-REENTRY-RESP` / completion-handler / session-delegate response-consumption record for the official detail request, despite seeing its resume path. Therefore the actual successful response consumer remains below/aside from the currently hooked Objective-C completion/delegate surfaces or otherwise unobserved.
7. This trace rejects the simplified hypothesis “re-send the detail GET and the current page will refresh.” A raw detail GET is demonstrably insufficient in this runtime. It also shows that reproducing request URLs alone is not enough evidence to replay init/prepare: the missing piece is still the official host state/response consumer.
8. Current Sync still performs enhancer-owned GET + existing Reload handoff. In this trace the subsequent Reload again only delivered detail and did not rebuild UI, so Sync remains structurally incapable of proving visible refresh.

## Current interpretation

- The useful part of the user's packet-capture idea is confirmed: normal official entry provides a reproducible request sequence that differs from current Reload.
- The stronger version of the idea — “record one request and resend it” — is rejected by this trace. Official entry is a state transition plus `init → prepare → detail`, and the host's response-consumption owner is still not captured.
- Same low-level `NSURLSession` ownership does not imply same UI semantics. Official entry and failed Reload both use `session-1`; only the official path was entered through the host's real navigation/state transition.
- Do not promote `init/prepare/detail` into a replay recipe yet.

## Architecture retained / rejected routes

- `CEConversationContext` remains sole active identity authority; only validated exact `conversation/init` body ID may promote foreground identity.
- `CENetworkObserver` remains sole passive official-network observation owner.
- `CEAPIClient` remains sole enhancer-originated ChatGPT request owner.
- Server GET/init/prepare/detail delivery alone is not visible Sync/Reload completion.
- Do not manually replay init/prepare/detail yet. First prove which official host path consumes the successful response and updates UI.
- Do not call UIKit push/pop/setViewControllers, force stack shape, use History/sidebar navigation, alternate IDs, speculative `/resume`, extra route retries, watchdogs or timers.
- Diagnostic persistence remains sanitized: no Authorization, Cookie, account IDs, raw request templates, full headers/bodies or message contents.
- Project-header work remains paused; percentage work remains untouched.

## Next exact action

Create the next diagnostic candidate only to identify the missing official response/state consumer. Narrow scope: instrument the official detail task/session completion boundary and relevant public Foundation task lifecycle/response surfaces without originating requests or mutating navigation. Compare one normal official entry against one Reload. Do not implement production request replay until that trace proves a host-owned consumer/state-update entry point.