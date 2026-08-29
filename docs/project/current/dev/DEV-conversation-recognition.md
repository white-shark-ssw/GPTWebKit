# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / 同步最新消息 / 重载 / conversation recognition / sync / reload`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；当前重点重新调查官方客户端“进入一个已完成会话 → 请求服务端 → 消费响应 → 刷新当前 UI”的真实链路，再基于该证据重做 Sync / Reload。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。插件自行 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；网络请求只有在官方 host 的真实响应消费/UI 更新链被证明后，才能作为 Sync/Reload 实现依据。

## Resume identity / conflict guard — 2026-08-30

- Baseline `feat/chatgpt-enhancer-v0.1` verified unchanged at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Working branch `feat/conversation-recognition` verified at `ad4a4718c498a9926ed553797ac9fb3e45df48c4`; Draft PR #2 remains open → `feat/chatgpt-enhancer-v0.1`.
- Parallel `DEV-conversation-usage` remains isolated on `feat/conversation-usage`, candidate alpha43. This task must not modify percentage-owned source/checkpoint.
- No product module is Frozen. Base did not materially advance. Branch / PR / head identities match repository truth.
- New reserved diagnostic candidate: `ENH-0.1.0-alpha58-reentry-network-trace` / `0.1.0-alpha58-reentry-network-trace`. It is unique versus recognition alpha42–57 and parallel alpha43.

## Latest authoritative user runtime evidence — 2026-08-30

The user reports that after extended real-device use, current Sync and Reload are **very likely not to work correctly**. This supersedes the old alpha57 assumption that improving same-ID route UI-proof detection was the next production direction.

The user proposes a new evidence-first direction:

1. Re-entering the App and opening an existing conversation necessarily causes the official ChatGPT client to request server data and then render/refresh the conversation.
2. Capture the real official request/response path used when opening an already-finished conversation, analogous to a packet trace.
3. Compare that successful official path with current enhancer Sync / Reload behavior.
4. Only after proving the response-consumption/UI-update owner, implement Reload/Sync from that real path rather than continuing to guess route variants.

This direction is accepted as an investigation plan, **not yet as proof that replaying one raw HTTP request through `CEAPIClient` will refresh the host UI**.

## Source finding driving the pivot

Current source confirms the existing implementation has a structural gap:

- `CEManualConversationReload.mm` does not invoke a proven official refresh owner. It opens `com.openai.chat://chatgpt.com/c/<exact-id>` and then observes whether same-ID network traffic and a UI rebuild happen.
- `CEPullLatestConversationResult` performs an enhancer-owned GET `/backend-api/conversation/<exact-id>`, parses server state, and if the response is finished it calls the same `CEManualConversationReload` route path.
- The enhancer-owned GET response is consumed by enhancer code / catalog analysis; there is no evidence that those bytes enter the official ChatGPT host view-model/reducer/UI response-consumption path.
- Existing network trace records method/path/IDs/status and navigation correlation, but does not yet provide enough structural evidence about the successful completed-conversation response and its capture/consumer path to justify production replay.

Therefore the next change is diagnostic only: improve the user-started trace around official completed-conversation re-entry, not add another speculative refresh route or request replay.

## Planned alpha58 diagnostic scope

Candidate: `0.1.0-alpha58-reentry-network-trace`.

Only while the existing user-started `会话识别记录` is active, capture sanitized evidence for relevant `conversation/init`, `conversation/prepare`, and exact conversation-detail traffic:

- request stage, method/path and exact conversation ID already permitted by existing trace rules;
- request JSON **top-level key names only**, never raw body/content;
- public NSURLSession/task observation source and bounded class/token correlation where available, without persisting pointer addresses;
- response status / byte count / MIME type;
- for a successful exact conversation-detail response: structural JSON summary only — conversation ID, top-level keys, `current_node`, mapping count, latest message ID/role/status/end_turn, update/create/finish timestamps and content type; **no message text/content**;
- capture-path marker showing whether the response was observed through a public completion-handler wrapper or session-delegate completion when provable.

No production Sync/Reload semantics change in alpha58. No replay, `/resume`, route retry, timer/watchdog, forced navigation mutation, History/sidebar navigation or percentage work is added.

## Prior alpha56/57 evidence retained

- Alpha56 trace `62313B1B-56B2-4F4C-A1B3-A658FDE8067D` proved one same-current custom route could replace active attached nav `nav-1` with `nav-2`; exact same-ID init/prepare/detail followed and the user saw one visible refresh.
- Alpha57 changed UI rebuild proof so nav-controller replacement could count as ephemeral UI evidence when exact request delivery was also observed.
- Alpha57 build/test source `fe48c56350720127786670d9fe37e28280905055`; Actions `33083945220`, job `98558346397`; post-CI cleanup/current head `ad4a4718c498a9926ed553797ac9fb3e45df48c4`.
- Alpha57 reached **Code written → CI passed → Artifact produced; Runtime/manual was Pending**. The new 2026-08-30 user result rejects treating that route-based direction as reliable production behavior.

## Architecture retained / rejected routes

- `CEConversationContext` remains sole active identity authority; only validated exact `conversation/init` body ID may promote foreground identity.
- `CENetworkObserver` remains sole passive official-network observation owner.
- `CEAPIClient` remains sole enhancer-originated ChatGPT request owner.
- Server GET/init/prepare/detail delivery alone is not visible Sync/Reload completion.
- Do not manually replay init/prepare/detail yet. First prove which official host path consumes the successful response and updates UI.
- Do not call UIKit push/pop/setViewControllers, force stack shape, use History/sidebar navigation, alternate IDs, speculative `/resume`, extra route retries, watchdogs or timers.
- Diagnostic persistence must remain sanitized: no Authorization, Cookie, account IDs, raw request templates, full headers/bodies or message contents.
- Project-header work remains paused; percentage work remains untouched.

## Validation state

- Alpha57: **Code written → CI passed → Artifact produced → latest broad runtime reliability rejected by user.** Not Stable/Frozen.
- Alpha58: **Candidate identity reserved; code not yet written at this checkpoint update.**

## Next exact action

Implement the bounded alpha58 network/re-entry diagnostics on `feat/conversation-recognition`, synchronize candidate identity, build it in isolated CI, then have the user record one sequence: start trace → use official UI to enter an already-finished target conversation and wait for it to fully render → press `同步最新消息` once → press `重载` once → finish/export the trace. Compare the successful official entry path against the two enhancer actions before any production request-replay implementation.