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
- Validation: **Code written → CI passed → Artifact produced. Runtime/manual pending.** Nothing Stable/Frozen.

### Alpha60 diagnostic scope

Alpha59 exposed a blind spot: its runtime-owner mapper filtered classes by exact raw `class_getImageName(cls) == _dyld_get_image_name(0)` string equality. Trace `897A6818-776A-44FC-84BA-21E0501A6A9A` returned `hostClasses=0`, but that alone cannot prove “no main-image ObjC classes” because iOS path aliases such as `/var/...` versus `/private/var/...` can make equivalent image paths compare unequal.

Alpha60 changes diagnostics only:

1. canonicalize main executable, class-image and app-bundle paths before ownership comparison;
2. independently verify main-image ownership through each method IMP's `dladdr(...).dli_fbase == mainBase`, so raw path mismatch cannot hide a true main-image method;
3. run direct `dladdr` resolution on the already-observed App `1.2026.202` `ChatGPT + offset` references and record image/symbol/symbol-start delta without persisting raw pointer addresses;
4. enumerate only bounded conversation/chat/thread/message/history/route/sidebar/navigation-related runtime classes located inside the ChatGPT App bundle and record the owning image basename;
5. invoke or swizzle none of the discovered methods; production Sync/Reload remains unchanged.

No Authorization, Cookie, account IDs, raw request/response bodies, request templates, message contents or raw pointer addresses are persisted.

## Authoritative alpha59 runtime evidence — trace 897A6818-776A-44FC-84BA-21E0501A6A9A

App `1.2026.202`, enhancer `0.1.0-alpha59-runtime-owner-map`.

1. Official entry into finished conversation `6a9343e3-5650-83ee-8d4e-cd0e1e21a361` again emitted exact `init → prepare → detail` on the same `session-1`: init at `1788036103011`, prepare +83 ms, detail +2 ms after prepare.
2. Alpha59's runtime mapper then emitted `RUNTIME-OWNER ... hostClasses=0 hostMethods=0 semanticClasses=0`. This is **inconclusive diagnostic output**, not proof that the relevant ChatGPT path has no ObjC runtime representation, because the mapper used raw image-path equality.
3. Reload began from exact current ID and the same attached `SwiftUI.UIKitNavigationController` `nav-1`, count 1. The custom route opened successfully.
4. Reload emitted exact detail GET first (`task-5`) about 58 ms after `open-route`, then an exact prepare (`task-6`) about 355 ms after that detail. **No exact init appeared.**
5. Despite detail + exact prepare delivery, the active nav instance stayed `nav-1`, no UI disappear/rebuild was observed across all 14 verification polls, and Reload correctly finished failure: `requestObserved=YES`, `uiRebuildObserved=NO`.
6. This supersedes the overly simple alpha58 statement that failed Reload always produces “detail only”. The durable distinction is stronger: the official successful path begins with exact init and quickly runs `init → prepare → detail`; a failed same-current route may produce `detail → prepare` without init and still not refresh the UI.
7. Therefore **prepare presence is not Reload completion evidence**, and manually replaying `prepare` remains unjustified. The missing official state transition / init owner is still the important boundary to identify.
8. No `NAV-MUTATION` occurred in this run; the modern side-menu/SwiftUI host can change/open a conversation without the older public UINavigationController mutation pattern being visible. Old nav traces remain historical evidence, not a universal transition recipe.

## Architecture retained / rejected routes

- `CEConversationContext` remains the sole active identity authority; only validated exact `POST /backend-api/conversation/init` body ID may promote foreground identity.
- `CENetworkObserver` remains sole passive official-network observation owner; `CEAPIClient` remains sole enhancer-originated ChatGPT request owner.
- Server GET/init/prepare/detail delivery alone is not visible Sync/Reload completion.
- Do not manually replay init/prepare/detail; do not infer success from prepare being emitted.
- Do not call UIKit push/pop/setViewControllers, force stack shape, use History/sidebar automation, alternate IDs, speculative `/resume`, retries, timers or watchdogs.
- Do not invoke a private selector merely because runtime mapping places it near a stack offset. Symbol proximity is candidate-owner evidence only.
- Project-header work remains paused; percentage work remains untouched.

## Next exact action

Runtime-test the exact alpha60 artifact on the same ChatGPT App `1.2026.202`: start `会话识别记录` from Home or another conversation, enter one already-finished target normally, wait until rendered, press Reload exactly once, wait for final status, then export the trace. Analyze `RUNTIME-OWNER-DLADDR`, `RUNTIME-OWNER`, `RUNTIME-OWNER-REF`, and `RUNTIME-OWNER-CLASS` together with official `init → prepare → detail` and failed Reload ordering. If direct symbols/main-IMP mapping remains empty after canonicalization and IMP-base verification, treat that as stronger evidence the key owner is pure Swift/non-ObjC and move the next diagnostic to Swift/runtime metadata rather than guessing selectors.