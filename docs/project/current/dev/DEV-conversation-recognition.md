# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；侧栏 Rename / Export 保持被长按行作用域；继续完善 Sync/Reload 的真实完成语义。项目顶部标题按用户要求暂停。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。服务器 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；只有真实 UI refresh/rebuild 才能报告可见同步/重载完成。

## Resume identity / conflict guard — 2026-08-27

- Baseline `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Working branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; alpha57 post-CI cleanup/current head `ad4a4718c498a9926ed553797ac9fb3e45df48c4`.
- Parallel `DEV-conversation-usage` remains isolated on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Recognition work does not modify percentage-owned sources/checkpoint.
- Base did not advance. No product module is Frozen.
- Current candidate `ENH-0.1.0-alpha57-navigation-rebuild-proof` / `0.1.0-alpha57-navigation-rebuild-proof` is unique versus recognition alpha42–56 and parallel alpha43.

## Authoritative alpha56 runtime evidence — trace 62313B1B-56B2-4F4C-A1B3-A658FDE8067D

Enhancer `0.1.0-alpha56-navigation-instance-trace`, ChatGPT app `1.2026.202`, exact target `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7` / `优化会话识别v1`:

1. User explicitly observed one network fluctuation and one visible page refresh after pressing `同步最新消息`, but the enhancer ended with `已请求客户端刷新，但页面未发生刷新。` This is a runtime false-negative in the previous UI-proof detector.
2. Reload started with active attached key-window navigation controller token `nav-1`, `count=3`, `active=YES`, `attached=YES`.
3. The same-current custom route produced a distinct public `setViewControllers: 0 → 1` mutation. Exact same-ID `conversation/init`, exact `prepare`, and conversation detail GET followed.
4. By verification poll 1, the active attached key-window navigation controller was **different token `nav-2`**, `count=1`, `active=YES`, `attached=YES`. This proves the route replaced the active host navigation-controller instance rather than merely mutating the same instance in place.
5. Exact same-ID request delivery was observed and one-delivery suppression remained correct: no second/third route attempt occurred.
6. `CEConversationUIReloadEvidence` had `baselineUI=unproven` because the old scroll/anchor detector could not prove message content; it therefore missed the actual host UI-surface replacement despite the user-observed refresh.
7. Active attached navigation-controller replacement is accepted as **ephemeral UI rebuild proof only** when combined with the existing exact same-ID request proof. It is not identity evidence and does not authorize manual navigation mutation.

## Current candidate — alpha57 navigation rebuild proof

- **Candidate**: `ENH-0.1.0-alpha57-navigation-rebuild-proof` / `0.1.0-alpha57-navigation-rebuild-proof`.
- **Source baseline**: alpha56 cleanup head `ce9bf42d6c4d3afde125e01c03120adbdf6f718d`.
- **Build/test source**: `fe48c56350720127786670d9fe37e28280905055`.
- **Actions**: run `33083945220`, job `98558346397` — completed **success**.
- **CI bookkeeping**: `ef75624e24e60842afabde93f4151a39453f1c9f`.
- **Post-CI cleanup/current branch head**: `ad4a4718c498a9926ed553797ac9fb3e45df48c4`.
- **Post-CI compare**: build/test source → cleanup head changes only `.github/latest-enhancer-run-id` bookkeeping and removal of the temporary recognition-branch CI trigger; tested product source is unchanged.
- **Artifacts**:
  - package `ChatGPTEnhancer-0.1.0-alpha57-navigation-rebuild-proof`, id `9651296956`, Actions archive digest `sha256:c71bfab996a1f01a0634701b95bafb12111863dcc97e3bb4469728e567630cae`;
  - dylib `ChatGPTEnhancer-0.1.0-alpha57-navigation-rebuild-proof-dylib`, id `9651298129`, Actions archive digest `sha256:ccf2275eded12bd180741ef82d3685b1be21a8da33c8cf01c8b9cea823755fe3`;
  - extracted `ChatGPTEnhancer.dylib`: Mach-O 64-bit arm64, 614096 bytes, sha256 `2d7de7f8b424d62ba970bf8913da5b0f64ed11d60108d06db5a3b2a9b62a8a3d`.
- **Validation state**: **Code written → CI passed → Artifact produced. Runtime/manual/real-device: Pending.** Nothing Stable/Frozen.

## Alpha57 implementation

1. Exact-ID Sync/Reload route behavior, terminal 429 handling, and one-delivery suppression are unchanged.
2. `CEConversationUIReloadEvidence` snapshots now also capture the currently active attached `UINavigationController` object identity as an ephemeral in-memory value. No pointer is persisted.
3. `CECurrentConversationUIReloadSnapshotShowsRebuild` now returns true when both baseline and current active attached navigation identities exist and differ. Existing scroll-view replacement and anchor-turnover proof remain intact as independent evidence paths.
4. `CECurrentConversationUIReloadSnapshotHasContent` semantics are intentionally unchanged: navigation presence alone does not claim message-content proof.
5. Success still requires the existing exact same-ID request evidence **and** UI rebuild proof. Navigation replacement alone cannot report success.
6. The enhancer does not call `setViewControllers`, push, or pop; does not force stack shape; and does not turn navigation identity into a long-lived state owner.
7. No percentage, project-header, Catalog throttling, `/resume`, retry/watchdog/timer, History/sidebar navigation, alternate ID, or manual init/prepare replay change was added.

## Architecture retained / rejected routes

- `CEConversationContext` remains sole active identity authority; only validated exact `conversation/init` body ID promotes foreground identity.
- `CEAPIClient` remains sole enhancer-originated ChatGPT request owner.
- Server GET/init/prepare/detail delivery alone is not visible Sync/Reload completion.
- Active attached navigation-controller **replacement** is now an evidence-backed UI rebuild signal, but only as ephemeral UI evidence and only with exact request proof for success.
- Do not manually replay init/prepare, force a three-controller stack, directly call UIKit pop/push/setViewControllers as a refresh, use History/sidebar navigation, alternate IDs, `/resume`, extra route retries, watchdogs or timers.
- Project-header work remains paused; percentage work remains untouched.

## Next exact action

Hand the exact alpha57 artifact to the user. Runtime acceptance: open the same conversation, press `同步最新消息`, and verify that when the page visibly refreshes the final status is `✓ 当前会话页面已刷新` instead of the alpha56 false-negative. A short identity trace is useful but not mandatory if the visible refresh/status pair is unambiguous. Do not mark Stable/Frozen until this exact artifact is tested.