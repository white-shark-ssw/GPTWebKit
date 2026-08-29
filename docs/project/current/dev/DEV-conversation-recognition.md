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
- Validation: **Code written → CI passed → Artifact produced → Runtime/manual pending.** Nothing Stable/Frozen.

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
- Existing pre-alpha58 trace recorded method/path/IDs/status and navigation correlation, but not enough successful completed-conversation response/capture structure to justify production replay.

Therefore alpha58 changes diagnostics only. It does not add another speculative refresh route or request replay.

## Alpha58 diagnostic scope implemented

Only while the existing user-started `会话识别记录` is active, alpha58 records sanitized evidence for relevant `conversation/init`, `conversation/prepare`, and exact conversation-detail traffic:

- request stage, method/path and exact conversation ID already permitted by existing trace rules;
- request JSON **top-level key names only**, never raw body/content;
- per-process opaque NSURLSession/task tokens plus bounded public class/state/source information where available, without persisting pointer addresses;
- response status / byte count / MIME type;
- for a successful exact conversation-detail response: structural JSON summary only — conversation ID, top-level keys, `current_node`, mapping count, latest message ID/role/status/end_turn, update/create/finish timestamps and content type; **no message text/content**;
- capture-path marker showing whether the response was observed through a public completion-handler wrapper or session-delegate completion when provable.

No production Sync/Reload semantics changed. No replay, `/resume`, route retry, timer/watchdog, forced navigation mutation, History/sidebar navigation or percentage work was added.

## Prior alpha56/57 evidence retained

- Alpha56 trace `62313B1B-56B2-4F4C-A1B3-A658FDE8067D` proved one same-current custom route could replace active attached nav `nav-1` with `nav-2`; exact same-ID init/prepare/detail followed and the user saw one visible refresh.
- Alpha57 changed UI rebuild proof so nav-controller replacement could count as ephemeral UI evidence when exact request delivery was also observed.
- Alpha57 build/test source `fe48c56350720127786670d9fe37e28280905055`; Actions `33083945220`, job `98558346397`; post-CI cleanup head `ad4a4718c498a9926ed553797ac9fb3e45df48c4`.
- Alpha57 reached **Code written → CI passed → Artifact produced**. The new 2026-08-30 user result rejects treating that route-based direction as reliable production behavior.

## Architecture retained / rejected routes

- `CEConversationContext` remains sole active identity authority; only validated exact `conversation/init` body ID may promote foreground identity.
- `CENetworkObserver` remains sole passive official-network observation owner.
- `CEAPIClient` remains sole enhancer-originated ChatGPT request owner.
- Server GET/init/prepare/detail delivery alone is not visible Sync/Reload completion.
- Do not manually replay init/prepare/detail yet. First prove which official host path consumes the successful response and updates UI.
- Do not call UIKit push/pop/setViewControllers, force stack shape, use History/sidebar navigation, alternate IDs, speculative `/resume`, extra route retries, watchdogs or timers.
- Diagnostic persistence remains sanitized: no Authorization, Cookie, account IDs, raw request templates, full headers/bodies or message contents.
- Project-header work remains paused; percentage work remains untouched.

## Exact runtime procedure for alpha58

Use one already-finished conversation as the target and do not change targets during the recording:

1. Install/inject the alpha58 dylib artifact.
2. Start from Home or a different conversation.
3. Begin `会话识别记录` **before** opening the target conversation.
4. Enter the finished target conversation using ChatGPT's normal official UI/sidebar and wait until the latest answer is fully visible.
5. Press `同步最新消息` exactly once and wait for its final visible status.
6. Press `重载` exactly once and wait for its final visible status.
7. Finish/export `会话识别记录` and return that trace.

Do not press Sync/Reload repeatedly. The purpose is to compare one proven official entry with one Sync and one Reload in the same trace.

## Next exact action

Analyze the returned alpha58 trace. Compare the official-entry `NET-REENTRY-TRANSPORT` / `NET-REENTRY-RESP` sequence and response-capture provenance against Sync/Reload. Only if evidence identifies a host-owned refresh/response-consumption path should the next production candidate invoke/reuse that path. If alpha58 shows only raw network equivalence but different consumption ownership, do **not** implement raw CEAPIClient replay as UI refresh.