# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / 同步最新消息 / 重载 / conversation recognition / sync / reload`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；当前重点仍是证明官方“进入已完成会话 → host state transition → 请求/消费响应 → 刷新 UI”的真实 owner，再基于证据重做 Sync / Reload。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。插件自行 GET 成功不等于页面同步；same-ID 请求、prepare、detail 送达都不等于页面 Reload；只有官方 host 的真实状态/响应消费/UI 更新链被证明后才能作为生产实现依据。

## Resume identity / conflict guard — 2026-08-30

- Base `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Working branch `feat/conversation-recognition`; Draft PR #2 remains open / mergeable → `feat/chatgpt-enhancer-v0.1`.
- Alpha60 build/test source `8d371801c764b4a8da95e44e74c0a99fa3a0b126`; CI bookkeeping `192ad870a1fb8417d0616ff941966ad4049ab7f5` changed only `.github/latest-enhancer-run-id`; post-CI cleanup/current PR head `c0431e83d29299d8da22d2e8089e392a0936511d`.
- Compare `8d371801... → c0431e83...` changes only `.github/latest-enhancer-run-id` plus removal of the temporary recognition-branch CI trigger; tested product source is unchanged.
- Parallel `DEV-conversation-usage` remains isolated on `feat/conversation-usage`, candidate alpha43, PR #3 stacked on `feat/conversation-recognition`. Recognition work does not modify its percentage-owned UI/model files or checkpoint. Because the stacked base keeps advancing, usage must reconcile in its own task before its next final validation.
- No product module is Frozen.

## Current candidate — alpha60

- Candidate ID: `ENH-0.1.0-alpha60-runtime-image-map`.
- Product version: `0.1.0-alpha60-runtime-image-map`.
- Build/test source: `8d371801c764b4a8da95e44e74c0a99fa3a0b126`.
- Actions run `33274357066`; job `99158361042` — **passed**.
- CI bookkeeping: `192ad870a1fb8417d0616ff941966ad4049ab7f5`.
- Post-CI cleanup/current PR head: `c0431e83d29299d8da22d2e8089e392a0936511d`.
- Package artifact: id `9721043070`, Actions digest `sha256:a08284ace0c5ae8bd381ec5515d4ffc5cfda39b02a3186a4806aa29a4283ff03`.
- Dylib artifact: id `9721043178`, Actions archive digest `sha256:297f910d780a19e3f0212cb1c6fb9cb006144847c281f2e0ee406bf0f9c82338`.
- Extracted dylib: Mach-O 64-bit arm64, 634272 bytes, sha256 `1b227794c9133f022a26bc3a59aa60091984a06b7a31545f0fc840ce10ef0e95`.
- Validation: **Code written → CI passed → Artifact produced → Runtime/manual partially tested.** Nothing Stable/Frozen.

## Authoritative alpha60 runtime evidence — trace FE491226-23C8-4F76-8D4E-230A1840D930

App `1.2026.202`, enhancer `0.1.0-alpha60-runtime-image-map`.

1. Official entry into finished conversation `6a9343e3-5650-83ee-8d4e-cd0e1e21a361` again emitted exact `init → prepare → detail` on `session-1`: init at `1788036891780`, prepare +196 ms, detail +4 ms after prepare.
2. Alpha60 corrected alpha59's raw-path filter enough to enumerate **4991 app-bundle runtime classes** and 100 bounded semantic classes. Relevant Swift types were visible in the ChatGPT image, including `Conversations.DefaultConversationSummaryHandoffService`, `Conversations.DefaultConversationBranchingService`, `ConversationsInterface.ConversationCoordinatorError.PendingCompletionTurn`, and `ConversationFinalStream.RecoveryEventSource / State / Storage`.
3. Those relevant Swift runtime classes exposed `selectors=<none>`. Independently, alpha60 reported `mainIMPClasses=0`, `mainIMPMethods=0`, and every known reference returned `result=no-main-objc-method`. This is strong evidence that the current conversation transition/stream state owner is not exposed as an Objective-C selector surface suitable for the previous mapper. Do not guess private ObjC selectors from these class names.
4. Direct reconstruction of old textual backtrace offsets also failed as an address strategy. `network-48186293`, whose original trace frame is textually `ChatGPT + 48186293`, resolved from `mainBase + offset` to `LiveKitWebRTC` symbol `webrtc::BasicNetworkManager::set_vpn_list(...)`; the other known references were unresolved. Therefore the textual `ChatGPT + N` token must **not** be treated as a reliable `_dyld_get_image_header(0) + N` address recipe in this injected runtime.
5. An exact prepare occurred at `1788036897013` while the top controller was `_UIContextMenuActionsOnlyViewController`, **114 ms before** the Reload action target was captured. It is therefore not attributable to the Reload route. This reinforces that prepare traffic can be menu/UI-adjacent background activity and is not a refresh-completion signal.
6. Reload began at `1788036897127` on exact current ID and attached `nav-1` count 1. The route opened successfully; an exact detail GET followed ~34 ms later on the same `session-1`. No exact init followed and no Reload-attributable prepare followed before completion.
7. All verification polls stayed on the same attached `nav-1`; `uiRebuildObserved=NO`, `uiSawDisappear=NO`. Reload correctly finished failure with `requestObserved=YES`, `uiRebuildObserved=NO` and `已请求客户端刷新，但页面未发生刷新。`
8. Alpha60 therefore confirms both historical failed shapes can occur: alpha58/60 show route-attributable detail without init; alpha59 showed detail then prepare without init. The durable missing boundary remains the official host state transition that precedes exact init, not the presence/absence of prepare alone.

## Superseded alpha59 interpretation retained

Alpha59 trace `897A6818-776A-44FC-84BA-21E0501A6A9A` showed official exact `init → prepare → detail`, while the failed same-current route emitted detail then prepare with no init and no UI rebuild. Its `hostClasses=0` result was inconclusive because of raw image-path filtering; alpha60 supersedes that mapper result while retaining the network/UI evidence.

## Architecture retained / rejected routes

- `CEConversationContext` remains the sole active identity authority; only validated exact `POST /backend-api/conversation/init` body ID may promote foreground identity.
- `CENetworkObserver` remains sole passive official-network observation owner; `CEAPIClient` remains sole enhancer-originated ChatGPT request owner.
- Server GET/init/prepare/detail delivery alone is not visible Sync/Reload completion.
- Do not manually replay init/prepare/detail; do not infer success from prepare being emitted.
- Do not call UIKit push/pop/setViewControllers, force stack shape, use History/sidebar automation, alternate IDs, speculative `/resume`, retries, timers or watchdogs.
- Do not continue Objective-C selector guessing from semantic Swift class names; alpha60 found app-bundle Swift types but no usable main-image ObjC IMP surface.
- Do not reconstruct executable addresses from sanitized textual `ChatGPT + offset` tokens. Alpha60 proved `mainBase + offset` can resolve into an unrelated loaded image.
- Raw return addresses must remain memory-only. Sanitized diagnostics may persist resolved image name, symbol name and relative symbol delta, but not raw pointer values.
- Project-header work remains paused; percentage work remains untouched.

## Next exact action

Create the next diagnostic candidate only if continuing this investigation. Replace numeric-offset reconstruction with **event-time return-address resolution**: when official `init / prepare / detail` and failed Reload detail are observed, take `NSThread.callStackReturnAddresses` in memory, run `dladdr` immediately on each bounded frame, and persist only sanitized `image / symbol / symbol-relative delta / frame order` metadata. Do not persist raw addresses, do not invoke discovered symbols, do not add request replay or navigation mutation. Compare the actual resolved frames for one official entry versus one Reload. If symbols remain stripped, use the resolved image/module identity plus Swift runtime type evidence to choose the next narrow Swift-metadata diagnostic; do not return to ObjC selector guessing or textual `+ offset` arithmetic.