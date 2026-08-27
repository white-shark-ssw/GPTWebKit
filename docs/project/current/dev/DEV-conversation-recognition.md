# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；侧栏 Rename / Export 保持被长按行作用域；继续完善 Sync/Reload 的真实完成语义。项目顶部标题按用户要求暂停。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。服务器 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；只有真实 UI refresh/rebuild 才能报告可见同步/重载完成。

## Resume identity / conflict guard — 2026-08-27

- Baseline `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Working branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; alpha56 post-CI cleanup/current head `ce9bf42d6c4d3afde125e01c03120adbdf6f718d`.
- Parallel `DEV-conversation-usage` remains isolated on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Recognition work does not modify percentage-owned sources/checkpoint.
- Base did not advance. No product module is Frozen.
- Candidate `ENH-0.1.0-alpha56-navigation-instance-trace` / `0.1.0-alpha56-navigation-instance-trace` remains unique versus recognition alpha42–55 and parallel alpha43.

## Authoritative alpha55 runtime evidence — trace F042014D-8407-4910-A5DA-2A9399C26425

Enhancer `0.1.0-alpha55-navigation-mutation-trace`, ChatGPT app `1.2026.202`, 238 structured events:

1. Genuine conversation navigation repeatedly used the same public mutation pattern: current conversation stack `3 → 2` via `popViewControllerAnimated:` and target conversation `2 → 3` via `pushViewController:animated:`. The pop and push caller signatures were stable across three occurrences each.
2. Genuine target `push 2 → 3` preceded exact target `POST /backend-api/conversation/init` by about 128–135 ms, followed by exact `prepare` and detail GET. Network traffic therefore remains a consequence/evidence signal, not the navigation owner.
3. Same-A `同步最新消息` still targeted the correct exact A ID. The custom route did **not** show the genuine `3 → 2 → 3` pattern. It emitted one distinct `setViewControllers:` mutation with `beforeCount=0 → afterCount=1`, then exact same-A init/prepare/detail while refresh-path snapshots showed `navCount=1`; visible UI still did not rebuild.
4. This corrects one alpha54 detail: the custom route can produce exact init/prepare/detail, but doing so inside the one-controller navigation state is still insufficient for visible refresh.
5. The custom-route `0 → 1 setViewControllers:` caller signature is structurally different from genuine push/pop signatures. `beforeCount=0` suggests a newly initialized/different navigation-controller instance, but alpha55 did not record instance identity/attachment, so that remains unproven.
6. Delivery-aware suppression still worked: after same-ID request delivery was proven and no UI rebuild occurred, no second/third route was sent. No HTTP 429 occurred.

## Current candidate — alpha56 navigation instance trace

- **Candidate**: `ENH-0.1.0-alpha56-navigation-instance-trace` / `0.1.0-alpha56-navigation-instance-trace`.
- **Source baseline**: alpha55 cleanup head `4fba1dd7d450666510f83ec0d10e612e6e2a7290`.
- **First CI attempt**: Actions `33052810815`, job `98452184776` — **failed at compile**, no artifact. Exact error was a diagnostic-only syntax typo in `CENavigationInstanceTrace.mm` (`expected ')'`); corrected before the accepted candidate build.
- **Accepted build/test source**: `f2cee73312da7254d44053ec092f9e7643326d92`.
- **Accepted Actions**: run `33052999411`, job `98452810620` — completed **success**.
- **CI bookkeeping**: `6b69425e5c2284777b86890d0d967f1d3c45dcf5`.
- **Post-CI cleanup/current branch head**: `ce9bf42d6c4d3afde125e01c03120adbdf6f718d`.
- **Post-CI compare**: accepted build/test source → cleanup head changes only `.github/latest-enhancer-run-id` bookkeeping and removal of the temporary recognition-branch CI trigger; tested product source is unchanged.
- **Artifacts**:
  - package `ChatGPTEnhancer-0.1.0-alpha56-navigation-instance-trace`, id `9638389331`, Actions archive digest `sha256:c6eab9030b6b4d9b5957fbb864410d0bf0931785ee95d4d4ca098e8d13dae0fb`;
  - dylib `ChatGPTEnhancer-0.1.0-alpha56-navigation-instance-trace-dylib`, id `9638389813`, Actions archive digest `sha256:993c966dd8dbdcc7ceb805d8ad647df5b0dff0a06b97e31b61923792a89d9266`;
  - extracted `ChatGPTEnhancer.dylib`: arm64 Mach-O, 613776 bytes, sha256 `3af11e471dd986d7074619be4f0b224f28e90ec3b29c73dd31379f4bb37b3b42`.
- **Validation state**: **Code written → CI passed → Artifact produced. Runtime/manual/real-device: Pending.** Nothing Stable/Frozen.

## Alpha56 implementation

1. Production Sync/Reload behavior remains unchanged from alpha52+; alpha56 is diagnostic-only.
2. New `CENavigationInstanceTrace` assigns each observed public `UINavigationController` a stable per-process diagnostic token via associated-object metadata; no raw pointer/address is persisted.
3. Around the existing same-current refresh handoff it snapshots all foreground reachable navigation-controller instances and records bounded stack composition, visible controller class, attachment to a window, key-window status, whether the instance is the active navigation controller resolved from the top controller, and bounded parent/presenting/presented controller class metadata.
4. Snapshot reasons cover before route open, route-delivery completion and verification/finish observation so the custom-route `0 → 1` instance can be correlated with the actually attached/active host navigation instance.
5. Existing `NAV-MUTATION` remains passive observation only. The enhancer does not call pop/push/setViewControllers to change host navigation, does not fabricate stack entries, does not hard-code private Swift classes and originates no new ChatGPT request for this diagnostic.
6. No percentage, project-header, Catalog throttling, `/resume`, retry/watchdog/timer, History/sidebar navigation, alternate ID, or manual init/prepare replay change was added.

## Architecture retained / rejected routes

- `CEConversationContext` remains sole active identity authority; only validated exact `conversation/init` body ID promotes foreground identity.
- `CEAPIClient` remains sole enhancer-originated ChatGPT request owner.
- Server GET/init/prepare/detail delivery is not visible Sync/Reload completion.
- Navigation mutation and navigation-instance/attachment observations are evidence only until ownership is proven.
- Do not manually replay init/prepare, force a three-controller stack, directly call UIKit pop/push/setViewControllers as a refresh, use History/sidebar navigation, alternate IDs, `/resume`, extra route retries, watchdogs or timers.
- Project-header work remains paused; percentage work remains untouched.

## Next exact action

Hand the exact alpha56 artifact to the user. For runtime evidence, only a short same-current trace is required: open target conversation → begin `会话识别记录` → press `同步最新消息` once → wait for final status → finish/export. Compare `NAV-INSTANCE` tokens/attachment/active ownership around the custom-route `setViewControllers 0 → 1`. If this proves a different/off-path navigation instance, stop treating the custom route as a viable production refresh entry. If it proves the active host-owned instance is being replaced, use that evidence to choose the smallest next production candidate; do not guess or mutate navigation before that result.