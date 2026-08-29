# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / 同步最新消息 / 重载 / conversation recognition / sync / reload`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；当前重点重新调查官方客户端“进入一个已完成会话 → 请求服务端 → 消费响应 → 刷新当前 UI”的真实链路，再基于该证据重做 Sync / Reload。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。插件自行 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；网络请求只有在官方 host 的真实响应消费/UI 更新链被证明后，才能作为 Sync/Reload 实现依据。

## Resume identity / conflict guard — 2026-08-30

- Baseline `feat/chatgpt-enhancer-v0.1` verified unchanged at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Working branch `feat/conversation-recognition`; Draft PR #2 remains open / mergeable → `feat/chatgpt-enhancer-v0.1`.
- Before alpha59 edits, PR #2 head was verified as `c0fa017e6bda0a4d91701e687abae3c8d51d3304`, matching the alpha58 checkpoint.
- Alpha59 build/test source is `76f83fcf6a53bebd4c8067b2bde44a4edb4a0dfc`; CI bookkeeping commit `21d7e92443052cec1afc8aaa1576b7d773e56138` was verified to modify only `.github/latest-enhancer-run-id`; post-CI cleanup/current PR head is `e86b8670fb8de4888e76fdc41f84f4e226275136`.
- Parallel `DEV-conversation-usage` remains on `feat/conversation-usage`, candidate alpha43, PR #3 stacked on `feat/conversation-recognition`. Its changed source is percentage-specific plus shared candidate/build identity files (`CECore.mm`, `build.sh`, workflow/bootstrap). This recognition task does not modify the percentage-owned UI/model files or its checkpoint. Advancing the recognition branch is an expected stacked-base change; the percentage branch must be reconciled in its own task before its next final validation.
- No product module is Frozen. Base remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.

## Current candidate — alpha59

- Candidate ID: `ENH-0.1.0-alpha59-runtime-owner-map`.
- Product version: `0.1.0-alpha59-runtime-owner-map`.
- Branch: `feat/conversation-recognition`; Draft PR #2.
- Build/test source: `76f83fcf6a53bebd4c8067b2bde44a4edb4a0dfc`.
- Actions run `33273831978`; job `99156971862` — **passed**.
- CI bookkeeping commit: `21d7e92443052cec1afc8aaa1576b7d773e56138` — only `.github/latest-enhancer-run-id` changed.
- Post-CI cleanup/current PR head: `e86b8670fb8de4888e76fdc41f84f4e226275136`.
- Package artifact: id `9720892970`, Actions digest `sha256:41838f67c629f3cf50e3d18260b304c65b57cec3dcddd1ad6df232256d471709`.
- Dylib artifact: id `9720893086`, Actions archive digest `sha256:3907409a25eaaa40c8dfe954bc7dc53aa4cad802ad4fe4a801d7dca7fb5d4044`.
- Extracted dylib: Mach-O 64-bit arm64, 633984 bytes, sha256 `a84a06d9ec29f2e9bdb84d7e35438939f9303d94bf01e969264ef26c0e9aa801`.
- Validation: **Code written → CI passed → Artifact produced. Runtime/manual pending.** Nothing Stable/Frozen.

### Alpha59 evidence-backed scope

Alpha58 already proved that official finished-conversation entry and failed same-current Reload share the same low-level `__NSURLSessionLocal` transport but differ in host state semantics, and that existing public completion/delegate hooks do not reveal the successful detail-response consumer. Alpha59 therefore does **not** add another network replay or unknown private hook.

A new diagnostic module `CEHostRuntimeOwnerTrace` is started only from the existing `CEBootstrap` owner. While the user-started identity trace is active and `CEConversationContext` changes to an exact target, it:

1. enumerates Objective-C runtime classes owned by the ChatGPT main executable without invoking their methods;
2. for App `1.2026.202`, maps the exact `ChatGPT + offset` frames already observed in alpha58 (`76920605`, `48186293`, `76937441`, `82300348`, `82123672`, `1884732`, `12860372`) to the nearest main-image Objective-C method IMP offsets;
3. records signed delta and a `near64k` marker so a merely distant nearest symbol cannot be mistaken for proof;
4. emits a bounded inventory of main-image class names containing `conversation/chat/thread/message/history/route/sidebar/navigation` and up to 24 related selectors per class;
5. if the installed ChatGPT version is not exactly `1.2026.202`, marks the alpha58 offset map non-comparable and does not apply those numeric references.

This diagnostic persists no raw pointer addresses, request/response bodies, message contents, Authorization, Cookie, account IDs or request templates. It does not invoke discovered selectors, swizzle unknown private methods, originate requests, mutate navigation, or change Sync/Reload behavior.

## Superseded candidate — alpha58

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
3. All three official requests were observed at `NSURLSessionTask resume` on the same public transport owner: opaque `session-1`, class `__NSURLSessionLocal`.
4. The two tested Reload attempts did **not** reproduce the official sequence. Each route produced only one exact detail GET on the same `session-1`, with no exact init/prepare preceding it.
5. Both Reload attempts proved same-ID detail request delivery but produced no UI rebuild across the full verification window; each correctly ended with `requestObserved=YES`, `uiRebuildObserved=NO`.
6. Alpha58 did not capture a `NET-REENTRY-RESP` / completion-handler / session-delegate response-consumption record for the official detail request, despite seeing its resume path. Therefore the actual successful response consumer remains below/aside from the currently hooked Objective-C completion/delegate surfaces or otherwise unobserved.
7. This trace rejects the simplified hypothesis “re-send the detail GET and the current page will refresh.” A raw detail GET is demonstrably insufficient in this runtime. It also shows that reproducing request URLs alone is not enough evidence to replay init/prepare: the missing piece is still the official host state/response consumer.
8. Current Sync still performs enhancer-owned GET + existing Reload handoff. In this trace the subsequent Reload again only delivered detail and did not rebuild UI, so Sync remains structurally incapable of proving visible refresh.

## Architecture retained / rejected routes

- `CEConversationContext` remains sole active identity authority; only validated exact `conversation/init` body ID may promote foreground identity.
- `CENetworkObserver` remains sole passive official-network observation owner.
- `CEAPIClient` remains sole enhancer-originated ChatGPT request owner.
- Server GET/init/prepare/detail delivery alone is not visible Sync/Reload completion.
- Do not manually replay init/prepare/detail yet. First prove which official host path consumes the successful response and updates UI.
- Do not call UIKit push/pop/setViewControllers, force stack shape, use History/sidebar navigation, alternate IDs, speculative `/resume`, extra route retries, watchdogs or timers.
- Do not invoke alpha59-discovered private selectors merely because they are near a stack offset. Near-symbol evidence is candidate-owner evidence only; invocation requires a separate runtime proof.
- Diagnostic persistence remains sanitized: no Authorization, Cookie, account IDs, raw request templates, full headers/bodies or message contents.
- Project-header work remains paused; percentage work remains untouched.

## Next exact action

Runtime-test the exact alpha59 artifact on ChatGPT App `1.2026.202`: start `会话识别记录` from Home or a different conversation, enter one already-finished target via normal official UI/sidebar, wait until fully rendered, press Reload exactly once and wait for its final status, then finish/export the trace. Analyze `RUNTIME-OWNER`, `RUNTIME-OWNER-REF`, `RUNTIME-OWNER-CLASS` together with official `NAV-MUTATION` / `REFRESH-PATH` and failed Reload evidence. If the reference frames map closely to a semantically plausible Objective-C owner, design only a later narrow observation/invocation proof; if they do not, treat that as evidence that the important frames are likely pure Swift/non-Objective-C and do not guess private selectors.