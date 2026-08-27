# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；侧栏 Rename / Export 保持被长按行作用域；继续完善 Sync/Reload 的真实完成语义。项目顶部标题按用户要求暂停。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。服务器 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；只有真实 UI refresh/rebuild 才能报告可见同步/重载完成。

## Resume identity / conflict guard — 2026-08-27

- Baseline `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Working branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; alpha55 cleanup/current head rechecked at `4fba1dd7d450666510f83ec0d10e612e6e2a7290`; PR remains open/draft/mergeable.
- Parallel `DEV-conversation-usage` remains isolated on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Recognition work does not modify percentage-owned sources/checkpoint.
- Base did not advance. No product module is Frozen.
- Alpha55 identity is unique. Next candidate allocated: `ENH-0.1.0-alpha56-navigation-instance-trace` / `0.1.0-alpha56-navigation-instance-trace`.

## Alpha55 build identity

- Build/test source `64038907a5e4daadf1f7917558ea82c19aa2c5c7`; Actions `33046416498`, job `98431347604` passed.
- CI bookkeeping `f1562b55d9848b55e84c902a95b685ce6c0aeb1a`; cleanup/current head `4fba1dd7d450666510f83ec0d10e612e6e2a7290`.
- Artifacts: package id `9635814798`; dylib id `9635815423`; extracted dylib sha256 `616bf42340b9d5934d09fea9a0f8ac04a4174dff3e0fdf92f2f5b7a9bc61560c`.
- Alpha55 is now **Runtime/manual/real-device partially tested**, not Stable/Frozen.

## Authoritative alpha55 runtime evidence — trace F042014D-8407-4910-A5DA-2A9399C26425

Enhancer `0.1.0-alpha55-navigation-mutation-trace`, ChatGPT app `1.2026.202`, 238 structured events:

1. Genuine conversation navigation repeatedly uses the same public mutation pattern: current conversation stack `3 → 2` via `popViewControllerAnimated:` and target conversation `2 → 3` via `pushViewController:animated:`. The `3 → 2` pop caller signature is stable across three occurrences and includes the same ChatGPT offsets; the `2 → 3` push signature is stable across three occurrences.
2. Genuine target `push 2 → 3` precedes exact target `POST /backend-api/conversation/init` by about 128–135 ms, followed by exact `prepare` and detail GET. This further confirms network traffic follows host navigation mutation.
3. Returning from B to A shows the same `3 → 2` pop then `2 → 3` push pattern and restores exact A identity correctly.
4. Same-A `同步最新消息` still targets the correct exact A ID. The custom route does **not** show the genuine `3 → 2 → 3` mutation. Instead it emits one distinct `setViewControllers:` mutation with `beforeCount=0 → afterCount=1`, then exact same-A init (+191 ms), exact prepare (+356 ms from mutation) and detail, all observed at `navCount=1`; visible UI still does not rebuild.
5. This corrects one alpha54 detail: the custom route is capable in this run of producing exact init/prepare/detail, but doing so inside the one-controller navigation state still does not refresh the visible conversation. Therefore init/prepare/detail remains consequence/evidence, not sufficient refresh authority.
6. The `0 → 1 setViewControllers:` caller signature is structurally different from genuine push/pop signatures and appears only for the custom route. `beforeCount=0` strongly suggests a newly initialized/different navigation-controller instance, but alpha55 did not log object identity or attachment, so this must remain a hypothesis until correlated.
7. Delivery-aware suppression still works: after same-ID detail request delivery was proven and no UI rebuild occurred, no second/third route was sent. No 429 occurred.

## Alpha56 exact diagnostic scope

Build one final narrow diagnostic successor before production mutation work:

- keep production Sync/Reload unchanged;
- assign each observed `UINavigationController` a stable per-process diagnostic token (no pointer/address persistence);
- include nav token in `NAV-MUTATION` and refresh-path observations;
- record whether that nav is currently attached to a visible window/key window, whether it is the navigation controller resolved from the current top controller, and bounded parent/presentation class metadata before/after the mutation;
- keep existing bounded class composition and sanitized caller evidence;
- do not originate requests, do not call pop/push/setViewControllers, do not fabricate stack entries and do not hard-code private Swift classes.

The goal is to prove whether custom-route `0 → 1` belongs to a new/off-path navigation instance or replaces/becomes the active navigation instance. This is necessary before deciding whether any host refresh implementation is evidence-backed.

## Architecture retained / rejected routes

- `CEConversationContext` remains sole active identity authority; only validated exact `conversation/init` body ID promotes foreground identity.
- `CEAPIClient` remains sole enhancer-originated ChatGPT request owner.
- Server GET/init/prepare/detail delivery is not visible Sync/Reload completion.
- Navigation mutations are evidence only until instance/attachment ownership is proven.
- Do not manually replay init/prepare, force a three-controller stack, directly call UIKit pop/push/setViewControllers as a refresh, use History/sidebar navigation, alternate IDs, `/resume`, extra route retries, watchdogs or timers.
- Project-header work remains paused; percentage work remains untouched.

## Next exact action

Implement/build alpha56 navigation-instance trace on `feat/conversation-recognition`, then capture one short user-started sequence A → B → A → one `同步最新消息`. Compare nav tokens and attachment/active ownership for genuine pop/push versus custom-route `setViewControllers 0 → 1`. If that evidence proves a real host-owned entry path, move directly to the smallest production refresh candidate; otherwise stop rather than guessing.