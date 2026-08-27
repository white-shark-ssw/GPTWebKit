# DEV-conversation-recognition

## Status

**Active**

- **Work ID**: `DEV-conversation-recognition`
- **Routing aliases / keywords**: `优化会话识别 / 会话识别 / 当前会话识别 / 会话切换识别 / conversation recognition`
- **Task**: 精确识别 ChatGPT iOS 当前会话，并确保 Sync / Reload / Export / Rename 不串会话；侧栏 Rename / Export 保持被长按行作用域；继续完善 Sync/Reload 的真实完成语义。项目顶部标题按用户要求暂停。
- **Acceptance invariant**: 当前会话动作必须使用真实 exact conversation ID。HTTP 429 不得被插件短间隔自动重试放大。服务器 GET 成功不等于页面同步；same-ID request delivery 不等于页面 Reload；只有真实 UI refresh/rebuild 才能报告可见同步/重载完成。

## Resume identity / conflict guard — 2026-08-27

- Baseline `feat/chatgpt-enhancer-v0.1` rechecked unchanged at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- Working branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`; alpha55 post-CI cleanup/current head `4fba1dd7d450666510f83ec0d10e612e6e2a7290`. PR was open/draft/mergeable before alpha55 edits.
- Parallel `DEV-conversation-usage` rechecked unchanged at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43. Alpha55 does not touch percentage-owned sources/checkpoint.
- Base did not advance. No product module is Frozen.
- Candidate `ENH-0.1.0-alpha55-navigation-mutation-trace` / `0.1.0-alpha55-navigation-mutation-trace` is unique versus recognition alpha42–54 and parallel alpha43.

## Authoritative alpha54 runtime evidence

Trace `conversation-identity-1995A79E-71DF-4EBC-BB1E-A61D48871FD2.log`, enhancer `0.1.0-alpha54-task-creation-trace`, app `1.2026.202`:

- Genuine navigation showed ID-less init/prepare staging at public navigation depth 2 before exact target init/prepare/detail at depth 3.
- Exact B init was followed by exact prepare/detail within ~123 ms; exact A return had the same depth-3 structure.
- Same-A Sync/custom-route refresh produced detail only, no exact init/prepare, no UI rebuild, and showed a one-controller navigation stack. Delivery-aware suppression prevented extra route attempts.
- `REFRESH-CREATE=0` while refresh-relevant `REFRESH-PATH` records were present. The specific Objective-C NSURLSession task-creation selectors instrumented by alpha54 are therefore not the creation path for these host semantic requests in this runtime.
- Network caller tracing is no longer the preferred next direction. Do not manually replay init/prepare or force a three-controller stack.

## Current candidate — alpha55 navigation mutation trace

- **Candidate**: `ENH-0.1.0-alpha55-navigation-mutation-trace` / `0.1.0-alpha55-navigation-mutation-trace`.
- **Source baseline**: alpha54 cleanup head `aa00b1d164fd11e8f743e557b33eecd8dcb1bfd1`.
- **Build/test source**: `64038907a5e4daadf1f7917558ea82c19aa2c5c7`.
- **Actions**: run `33046416498`, job `98431347604` — completed **success**.
- **CI bookkeeping**: `f1562b55d9848b55e84c902a95b685ce6c0aeb1a`.
- **Post-CI cleanup/current branch head**: `4fba1dd7d450666510f83ec0d10e612e6e2a7290`.
- **Post-CI compare**: build/test source → cleanup head changes only `.github/latest-enhancer-run-id` and removal of the temporary recognition-branch CI trigger; tested product source is unchanged.
- **Artifacts**:
  - package `ChatGPTEnhancer-0.1.0-alpha55-navigation-mutation-trace`, id `9635814798`, Actions archive digest `sha256:2edbf8e2a7cc7b9f96ec907fd4fb396f8ef96ba723e987cd8587b264ef78a62e`;
  - dylib `ChatGPTEnhancer-0.1.0-alpha55-navigation-mutation-trace-dylib`, id `9635815423`, Actions archive digest `sha256:9f6b3e1bd95465c426efdecbfb14dc748a6bb34eed4817bddeb6c7027e9792b4`;
  - extracted `ChatGPTEnhancer.dylib`: arm64 Mach-O, sha256 `616bf42340b9d5934d09fea9a0f8ac04a4174dff3e0fdf92f2f5b7a9bc61560c`.
- **Validation state**: **Code written → CI passed → Artifact produced. Runtime/manual/real-device: Pending.** Nothing Stable/Frozen.

## Alpha55 implementation

1. Production Sync/Reload behavior is unchanged from alpha52+; alpha55 is diagnostic-only.
2. The existing identity-trace subsystem passively swizzles only public `UINavigationController` mutation entry points: `setViewControllers:`, `setViewControllers:animated:`, `pushViewController:animated:`, `popViewControllerAnimated:`, `popToViewController:animated:`, and `popToRootViewControllerAnimated:`.
3. `NAV-MUTATION` is emitted only while the user-started trace is recording and only when bounded controller-class count/composition actually changes. It records source selector, animated/main-thread flag, exact current context ID, before/after counts and class composition, visible controller classes, and bounded sanitized caller symbols.
4. A thread-local reentrancy guard prevents nested UIKit implementation calls from duplicating the same mutation trace.
5. The diagnostic does not perform navigation, does not fabricate stack entries, does not hard-code the observed Swift controller class, and originates no new ChatGPT request.
6. No percentage, project-header, Catalog throttling, `/resume`, retry/watchdog/timer, History/sidebar navigation, alternate ID, or manual init/prepare replay change was added.

## Architecture retained / rejected routes

- `CEConversationContext` remains sole active identity authority; only validated exact `conversation/init` body ID promotes foreground identity.
- `CEAPIClient` remains sole enhancer-originated request owner.
- Server GET/request delivery is not visible Sync/Reload completion.
- Navigation count/composition is diagnostic evidence only. Alpha55 observes public mutation entry points but does not authorize calling them for production refresh.
- Project-header work remains paused; percentage work remains untouched.

## Next exact action

Hand the exact alpha55 artifact to the user and capture one user-started trace: A visible → normal A → B → A → press `同步最新消息` once → wait for final status → export. Compare `NAV-MUTATION` selector/caller and before/after stack changes for genuine navigation versus the custom-route collapse. Only if a stable host-owned public mutation path is evidenced should production refresh implementation be considered.