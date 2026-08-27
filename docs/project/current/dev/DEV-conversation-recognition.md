# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；侧栏 Rename / Export 保持被长按行作用域；继续完善 Sync/Reload 的真实完成语义。项目顶部标题按用户要求暂停。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。服务器 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；只有真实 UI refresh/rebuild 才能报告可见同步/重载完成。

## Resume identity / conflict guard — 2026-08-27

- Baseline `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Working branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; alpha56 post-CI cleanup/current head rechecked at `ce9bf42d6c4d3afde125e01c03120adbdf6f718d`; PR remains open/draft/mergeable.
- Parallel `DEV-conversation-usage` remains isolated on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Recognition work does not modify percentage-owned sources/checkpoint.
- Base did not advance. No product module is Frozen.
- Alpha56 identity is unique. Next candidate allocated: `ENH-0.1.0-alpha57-navigation-rebuild-proof` / `0.1.0-alpha57-navigation-rebuild-proof`.

## Alpha56 build identity

- Candidate `ENH-0.1.0-alpha56-navigation-instance-trace` / `0.1.0-alpha56-navigation-instance-trace`.
- Accepted build/test source `f2cee73312da7254d44053ec092f9e7643326d92`; Actions `33052999411`, job `98452810620` passed.
- First attempt Actions `33052810815`, job `98452184776` failed compile on one diagnostic syntax typo and produced no artifact; it is not the accepted candidate.
- CI bookkeeping `6b69425e5c2284777b86890d0d967f1d3c45dcf5`; post-CI cleanup/current branch head `ce9bf42d6c4d3afde125e01c03120adbdf6f718d`.
- Artifacts: package id `9638389331`, digest `sha256:c6eab9030b6b4d9b5957fbb864410d0bf0931785ee95d4d4ca098e8d13dae0fb`; dylib id `9638389813`, Actions archive digest `sha256:993c966dd8dbdcc7ceb805d8ad647df5b0dff0a06b97e31b61923792a89d9266`; extracted dylib sha256 `3af11e471dd986d7074619be4f0b224f28e90ec3b29c73dd31379f4bb37b3b42`.
- Alpha56 is now **Runtime/manual/real-device partially tested**, not Stable/Frozen.

## Authoritative alpha56 runtime evidence — trace 62313B1B-56B2-4F4C-A1B3-A658FDE8067D

Enhancer `0.1.0-alpha56-navigation-instance-trace`, ChatGPT app `1.2026.202`, exact target `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7` / `优化会话识别v1`:

1. User explicitly observed one network fluctuation and one visible page refresh after pressing `同步最新消息`, but the enhancer ended with `已请求客户端刷新，但页面未发生刷新。` This is a runtime false-negative in the current UI-proof detector.
2. At Reload start and immediately before route delivery, the active attached key-window navigation controller was stable token `nav-1`, `count=3`, `active=YES`, `attached=YES`.
3. About 84 ms after Reload start the custom route created a distinct public navigation mutation `setViewControllers: 0 → 1`. Exact same-ID `conversation/init` followed about 153 ms after that mutation, then exact `prepare` + conversation detail GET about 162 ms later.
4. By verification poll 1, the active attached key-window navigation controller was **different token `nav-2`**, `count=1`, `active=YES`, `attached=YES`; the old active `nav-1` was no longer the active snapshot. This proves the route replaces the active host navigation-controller instance rather than merely mutating the same instance in place.
5. The exact same-ID request was observed (`source=detail`) and delivery-aware suppression remained correct: there was no second/third route attempt.
6. Existing `CEConversationUIReloadEvidence` started with `baselineUI=unproven` because its scroll/anchor snapshot could not prove message content. It therefore never set `uiRebuildObserved=YES`, even though the active attached navigation surface was replaced and the user visually observed a refresh.
7. The new evidence is sufficient to extend **UI rebuild proof only**: replacement of the active attached navigation-controller object across the same exact-ID route is a host UI-surface rebuild signal. It is not conversation identity evidence and does not authorize manual push/pop/setViewControllers.

## Alpha57 exact scope

Implement the smallest production proof correction:

- keep exact-ID Sync/Reload route behavior, terminal 429 handling and one-delivery suppression unchanged;
- extend `CEConversationUIReloadEvidence` snapshots with the current active attached `UINavigationController` object identity as ephemeral in-memory UI evidence;
- allow `CECurrentConversationUIReloadSnapshotShowsRebuild` to return true when the baseline active attached nav and current active attached nav are both present and are different objects;
- still require exact same-ID request evidence before reporting Reload/Sync visible success;
- do **not** change `CEConversationContext`, do not persist raw nav pointers, do not turn nav identity into a long-lived state owner, and do not call navigation mutation APIs;
- retain existing scroll/anchor proof as an independent UI-rebuild path;
- no percentage, project-header, Catalog throttling, `/resume`, retry/watchdog/timer, History/sidebar navigation, alternate ID, or manual init/prepare replay changes.

## Architecture retained / rejected routes

- `CEConversationContext` remains sole active identity authority; only validated exact `conversation/init` body ID promotes foreground identity.
- `CEAPIClient` remains sole enhancer-originated ChatGPT request owner.
- Server GET/init/prepare/detail delivery alone is not visible Sync/Reload completion.
- Active attached navigation-controller **replacement** may now be used as ephemeral UI rebuild proof only because alpha56 correlated it with the same exact-ID route and user-observed visible refresh.
- Do not manually replay init/prepare, force a three-controller stack, directly call UIKit pop/push/setViewControllers as a refresh, use History/sidebar navigation, alternate IDs, `/resume`, extra route retries, watchdogs or timers.
- Project-header work remains paused; percentage work remains untouched.

## Next exact action

Implement alpha57 on `feat/conversation-recognition`, run isolated CI/artifact validation, then hand the exact candidate to the user. Runtime acceptance: on the same-current `同步最新消息` path, if the route again replaces the active attached navigation controller and the exact same-ID request is observed, the final status must report page refresh instead of the alpha56 false-negative. Do not mark Stable/Frozen until that exact artifact is tested.